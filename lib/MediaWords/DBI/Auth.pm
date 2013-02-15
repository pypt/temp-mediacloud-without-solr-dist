package MediaWords::DBI::Auth;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

#
# Authentication helpers
#

use strict;
use warnings;

use Digest::SHA qw/sha256_hex/;
use Crypt::SaltedHash;
use MediaWords::Util::Mail;
use POSIX qw(strftime);
use URI::Escape;

use Data::Dumper;

# Generate random alphanumeric string (password or token) of the specified length
sub random_string($)
{
    my ( $num_bytes ) = @_;
    return join '', map +( 0 .. 9, 'a' .. 'z', 'A' .. 'Z' )[ rand( 10 + 26 * 2 ) ], 1 .. $num_bytes;
}

# Validate a password / password token with Crypt::SaltedHash; return 1 on success, 0 on error
sub _validate_hash($$)
{
    my ( $secret_hash, $secret ) = @_;

    # Determine salt (hash type should be placed in the hash)
    my $config = MediaWords::Util::Config::get_config;

    my $salt_len = $config->{ 'Plugin::Authentication' }->{ 'users' }->{ 'credential' }->{ 'password_salt_len' };
    if ( !$salt_len )
    {
        say STDERR "Salt length is 0";
        $salt_len = 0;
    }

    if ( Crypt::SaltedHash->validate( $secret_hash, $secret, $salt_len ) )
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

# Hash a password / password token with Crypt::SaltedHash; return hash on success, empty string on error
sub generate_hash($)
{
    my ( $secret ) = @_;

    # Determine salt and hash type
    my $config = MediaWords::Util::Config::get_config;

    my $salt_len = $config->{ 'Plugin::Authentication' }->{ 'users' }->{ 'credential' }->{ 'password_salt_len' };
    if ( !$salt_len )
    {
        say STDERR "Salt length is 0";
        $salt_len = 0;
    }

    my $hash_type = $config->{ 'Plugin::Authentication' }->{ 'users' }->{ 'credential' }->{ 'password_hash_type' };
    if ( !$hash_type )
    {
        say STDERR "Unable to determine the password hashing algorithm";
        return 0;
    }

    # Hash the password
    my $csh = Crypt::SaltedHash->new( algorithm => $hash_type, salt_len => $salt_len );
    $csh->add( $secret );
    my $secret_hash = $csh->generate;
    if ( !$secret_hash )
    {
        die "Unable to hash a secret.";
    }
    if ( !_validate_hash( $secret_hash, $secret ) )
    {
        say STDERR "Secret hash has been generated, but it does not validate.";
        return 0;
    }

    return $secret_hash;
}

# Fetch a list of available user roles
sub all_roles($)
{
    my ( $db ) = @_;

    my $roles = $db->query(
        <<"EOF"
        SELECT roles_id, role, description
        FROM auth_roles
        ORDER BY roles_id
EOF
    )->hashes;

    return $roles;
}

# Fetch a hash of basic user information (email, full name, notes); returns 0 on error
sub user_info($$)
{
    my ( $db, $email ) = @_;

    # Fetch readonly information about the user
    my $userinfo = $db->query(
        <<"EOF",
        SELECT users_id,
               email,
               full_name,
               notes
        FROM auth_users
        WHERE email = ?
        LIMIT 1
EOF
        $email
    )->hash;
    if ( !( ref( $userinfo ) eq 'HASH' and $userinfo->{ users_id } ) )
    {
        return 0;
    }

    return $userinfo;
}

# Fetch a hash of basic user information, password hash and assigned roles; returns 0 on error
sub user_auth($$)
{
    my ( $db, $email ) = @_;

    # Check if user exists and is active; if so, fetch user info,
    # password hash and a list of roles
    my $user = $db->query(
        <<"EOF",
        SELECT auth_users.users_id,
               auth_users.email,
               auth_users.password_hash,
               ARRAY_TO_STRING(ARRAY_AGG(role), ' ') AS roles
        FROM auth_users
            LEFT JOIN auth_users_roles_map
                ON auth_users.users_id = auth_users_roles_map.users_id
            LEFT JOIN auth_roles
                ON auth_users_roles_map.roles_id = auth_roles.roles_id
        WHERE auth_users.email = ?
              AND auth_users.active = true
        GROUP BY auth_users.users_id,
                 auth_users.email,
                 auth_users.password_hash
        ORDER BY auth_users.users_id
        LIMIT 1
EOF
        $email
    )->hash;

    if ( !( ref( $user ) eq 'HASH' and $user->{ users_id } ) )
    {
        return 0;
    }

    return $user;
}

# Post-successful login database tasks
sub post_successful_login($$)
{
    my ( $db, $email ) = @_;

    # Reset the password reset token (if any)
    $db->query(
        <<"EOF",
        UPDATE auth_users
        SET password_reset_token_hash = NULL
        WHERE email = ?
EOF
        $email
    );

    return 1;
}

# Validate password reset token; returns 1 if token exists and is valid, 0 otherwise
sub validate_password_reset_token($$$)
{
    my ( $db, $email, $password_reset_token ) = @_;

    if ( !( $email && $password_reset_token ) )
    {
        say STDERR "Email and / or password reset token is empty.";
        return 0;
    }

    # Fetch readonly information about the user
    my $password_reset_token_hash = $db->query(
        <<"EOF",
        SELECT users_id,
               email,
               password_reset_token_hash
        FROM auth_users
        WHERE email = ?
        LIMIT 1
EOF
        $email
    )->hash;
    if ( !( ref( $password_reset_token_hash ) eq 'HASH' and $password_reset_token_hash->{ users_id } ) )
    {
        say STDERR 'Unable to find user ' . $email . ' in the database.';
        return 0;
    }

    $password_reset_token_hash = $password_reset_token_hash->{ password_reset_token_hash };

    if ( _validate_hash( $password_reset_token_hash, $password_reset_token ) )
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

# Check if password fits the requirements; returns empty string on valid password, error message on invalid password
sub password_fits_requirements($$$)
{
    my ( $email, $password, $password_repeat ) = @_;

    if ( !$email )
    {
        return 'Email address is empty.';
    }

    if ( !( $password && $password_repeat ) )
    {
        return 'To set the password, please repeat the new password twice.';
    }

    if ( $password ne $password_repeat )
    {
        return 'Passwords do not match.';
    }

    if ( length( $password ) < 8 or length( $password ) > 120 )
    {
        return 'Password must be 8 to 120 characters in length.';
    }

    if ( $password eq $email )
    {
        return 'New password is your email address; don\'t cheat!';
    }

    return '';
}

# Change password; returns error message on failure, empty string on success
sub _change_password($$$$)
{
    my ( $db, $email, $password_new, $password_new_repeat ) = @_;

    my $password_validation_message = password_fits_requirements( $email, $password_new, $password_new_repeat );
    if ( $password_validation_message )
    {
        return $password_validation_message;
    }

    # Hash + validate the password
    my $password_new_hash = generate_hash( $password_new );
    if ( !$password_new_hash )
    {
        return 'Unable to hash a new password.';
    }

    # Set the password hash
    $db->query(
        <<"EOF",
        UPDATE auth_users
        SET password_hash = ?
        WHERE email = ?
EOF
        $password_new_hash, $email
    );

    # Send email
    my $now           = strftime( "%a, %d %b %Y %H:%M:%S %z", localtime( time() ) );
    my $email_subject = 'Your password has been changed';
    my $email_message = <<"EOF";
Your Media Cloud password has been changed on $now.

If you made this change, no need to reply - you're all set.

If you did not request this change, please contact Media Cloud support at
www.mediacloud.org.
EOF

    if ( !MediaWords::Util::Mail::send( $email, $email_subject, $email_message ) )
    {
        return 'The password has been changed, but I was unable to send an email notifying you about the change.';
    }

    # Success
    return '';
}

# Change password by entering old password; returns error message on failure, empty string on success
sub change_password_via_profile($$$$$)
{
    my ( $db, $email, $password_old, $password_new, $password_new_repeat ) = @_;

    if ( !$password_old )
    {
        return 'To change the password, please enter an old ' . 'password and then repeat the new password twice.';
    }

    if ( $password_old eq $password_new )
    {
        return 'Old and new passwords are the same.';
    }

    # Validate old password (password hash is located in $c->user->password, but fetch
    # the hash from the database again because that hash might be outdated (e.g. if the
    # password has been changed already))
    my $db_password_old = $db->query(
        <<"EOF",
        SELECT users_id,
               email,
               password_hash
        FROM auth_users
        WHERE email = ?
        LIMIT 1
EOF
        $email
    )->hash;

    if ( !( ref( $db_password_old ) eq 'HASH' and $db_password_old->{ users_id } ) )
    {
        return 'Unable to find the user in the database.';
    }
    $db_password_old = $db_password_old->{ password_hash };

    # Validate the password
    if ( !_validate_hash( $db_password_old, $password_old ) )
    {
        return 'Old password is incorrect.';
    }

    # Execute the change
    return _change_password( $db, $email, $password_new, $password_new_repeat );
}

# Change password with a password token sent by email; returns error message on failure, empty string on success
sub change_password_via_token($$$$$)
{
    my ( $db, $email, $password_reset_token, $password_new, $password_new_repeat ) = @_;

    if ( !$password_reset_token )
    {
        return 'Password reset token is empty.';
    }

    # Validate the token once more (was pre-validated in controller)
    if ( !validate_password_reset_token( $db, $email, $password_reset_token ) )
    {
        return 'Password reset token is invalid.';
    }

    # Execute the change
    my $error_message = _change_password( $db, $email, $password_new, $password_new_repeat );
    if ( $error_message )
    {
        return $error_message;
    }

    # Unset the password reset token
    post_successful_login( $db, $email );

    return $error_message;
}

# Fetch and return a list of users and their roles; returns an arrayref
sub list_of_users($)
{
    my ( $db ) = @_;

    # List a full list of roles near each user because (presumably) one can then find out
    # whether or not a particular user has a specific role faster.
    my $users = $db->query(
        <<"EOF"
        SELECT
            auth_users.users_id,
            auth_users.email,
            auth_users.full_name,
            auth_users.notes,
            auth_users.active,

            -- Role from a list of all roles
            all_roles.role,

            -- Boolean denoting whether the user has that particular role
            ARRAY(     
                SELECT r_auth_roles.role
                FROM auth_users AS r_auth_users
                    INNER JOIN auth_users_roles_map AS r_auth_users_roles_map
                        ON r_auth_users.users_id = r_auth_users_roles_map.users_id
                    INNER JOIN auth_roles AS r_auth_roles
                        ON r_auth_users_roles_map.roles_id = r_auth_roles.roles_id
                WHERE auth_users.users_id = r_auth_users.users_id
            ) @> ARRAY[all_roles.role] AS user_has_that_role

        FROM auth_users,
             (SELECT role FROM auth_roles ORDER BY roles_id) AS all_roles

        ORDER BY auth_users.users_id
EOF
    )->hashes;

    my $unique_users = {};

    # Make a hash of unique users and their rules
    for my $user ( @{ $users } )
    {
        my $users_id = $user->{ users_id } + 0;
        $unique_users->{ $users_id }->{ 'users_id' }  = $users_id;
        $unique_users->{ $users_id }->{ 'email' }     = $user->{ email };
        $unique_users->{ $users_id }->{ 'full_name' } = $user->{ full_name };
        $unique_users->{ $users_id }->{ 'notes' }     = $user->{ notes };
        $unique_users->{ $users_id }->{ 'active' }    = $user->{ active };

        if ( !ref( $unique_users->{ $users_id }->{ 'roles' } ) eq 'HASH' )
        {
            $unique_users->{ $users_id }->{ 'roles' } = {};
        }

        $unique_users->{ $users_id }->{ 'roles' }->{ $user->{ role } } = $user->{ user_has_that_role };
    }

    $users = [];
    foreach my $users_id ( sort { $a <=> $b } keys %{ $unique_users } )
    {
        push( @{ $users }, $unique_users->{ $users_id } );
    }

    return $users;
}

# Activate / deactivate user; returns error message on error, empty string on success
sub make_user_active($$$)
{
    my ( $db, $email, $active ) = @_;

    # Check if user exists
    my $userinfo = user_info( $db, $email );
    if ( !$userinfo )
    {
        return "User with email address '$email' does not exist.";
    }

    my $sql = '';
    if ( $active )
    {
        $sql = <<"EOF";
            UPDATE auth_users
            SET active = true
            WHERE email = ?
EOF
    }
    else
    {
        $sql = <<"EOF";
            UPDATE auth_users
            SET active = false
            WHERE email = ?
EOF
    }

    $db->query( $sql, $email );

    return '';
}

# Add new user; returns error message on error, empty string on success
sub add_user($$$$$$$)
{
    my ( $db, $email, $password, $password_repeat, $full_name, $notes, $roles ) = @_;

    my $password_validation_message = password_fits_requirements( $email, $password, $password_repeat );
    if ( $password_validation_message )
    {
        return $password_validation_message;
    }

    # Check if user already exists
    my $userinfo = user_info( $db, $email );
    if ( $userinfo )
    {
        return "User with email address '$email' already exists.";
    }

    # Hash + validate the password
    my $password_hash = generate_hash( $password );
    if ( !$password_hash )
    {
        return 'Unable to hash a new password.';
    }

    # Begin transaction
    $db->dbh->{ AutoCommit } = 0;

    # Create the user
    $db->query(
        <<"EOF",
        INSERT INTO auth_users (email, password_hash, full_name, notes)
        VALUES (?, ?, ?, ?)
EOF
        $email, $password_hash, $full_name, $notes
    );

    # Fetch the user's ID
    $userinfo = user_info( $db, $email );
    if ( !$userinfo )
    {
        return "I've attempted to create the user but it doesn't exist.";
    }
    my $users_id = $userinfo->{ users_id };

    # Create roles
    my $sql = 'INSERT INTO auth_users_roles_map (users_id, roles_id) VALUES (?, ?)';
    my $sth = $db->dbh->prepare_cached( $sql );
    for my $roles_id ( @{ $roles } )
    {
        $sth->execute( $users_id, $roles_id );
    }
    $sth->finish;

    # End transaction
    $db->dbh->{ AutoCommit } = 1;

    # Success
    return '';
}

# Delete user; returns error message on error, empty string on success
sub delete_user($$)
{
    my ( $db, $email ) = @_;

    # Check if user exists
    my $userinfo = MediaWords::DBI::Auth::user_info( $db, $email );
    if ( !$userinfo )
    {
        return "User with email address '$email' does not exist.";
    }

    # Delete the user (PostgreSQL's relation will take care of 'auth_users_roles_map')
    $db->query(
        <<"EOF",
        DELETE FROM auth_users
        WHERE email = ?
EOF
        $email
    );

    return '';
}

# Prepare for password reset by emailing the password reset token; returns error message on failure, empty string on success
sub send_password_reset_token($$$)
{
    my ( $db, $email, $password_reset_link ) = @_;

    if ( !$email )
    {
        return 'Email address is empty.';
    }
    if ( !$password_reset_link )
    {
        return 'Password reset link is empty.';
    }

    # Check if the email address exists in the user table; if not, pretend that
    # we sent the password reset link with a "success" message.
    # That way the adversary would not be able to find out which email addresses
    # are active users.
    #
    # (Possible improvement: make the script work for the exact same amount of
    # time in both cases to avoid timing attacks)
    my $user_exists = $db->query(
        <<"EOF",
        SELECT users_id,
               email
        FROM auth_users
        WHERE email = ?
        LIMIT 1
EOF
        $email
    )->hash;

    if ( !( ref( $user_exists ) eq 'HASH' and $user_exists->{ users_id } ) )
    {

        # User was not found, so set the email address to an empty string, but don't
        # return just now and continue with a rather slowish process of generating a
        # password reset token (in order to reduce the risk of timing attacks)
        $email = '';
    }

    # Generate the password reset token
    my $password_reset_token = random_string( 64 );
    if ( !length( $password_reset_token ) )
    {
        return 'Unable to generate a password reset token.';
    }

    # Hash + validate the password reset token
    my $password_reset_token_hash = generate_hash( $password_reset_token );
    if ( !$password_reset_token_hash )
    {
        return 'Unable to hash a password reset token.';
    }

    # Set the password token hash in the database
    # (if the email address doesn't exist, this query will do nothing)
    $db->query(
        <<"EOF",
        UPDATE auth_users
        SET password_reset_token_hash = ?
        WHERE email = ? AND email != ''
EOF
        $password_reset_token_hash, $email
    );

    # If we didn't find an email address in the database, we return here with a fake
    # "success" message
    if ( !length( $email ) )
    {
        return '';
    }

    $password_reset_link =
      $password_reset_link . '?email=' . uri_escape( $email ) . '&token=' . uri_escape( $password_reset_token );
    print STDERR "Full password reset link: $password_reset_link\n";

    # Send email
    my $email_subject = 'Password reset link';
    my $email_message = <<"EOF";
Someone (hopefully that was you) has requested a link to change your password,
and you can do this through the link below:

$password_reset_link

Your password won't change until you access the link above and create a new one.

If you didn't request this, please ignore this email or contact Media Cloud
support at www.mediacloud.org.
EOF

    if ( !MediaWords::Util::Mail::send( $email, $email_subject, $email_message ) )
    {
        return 'The password has been changed, but I was unable to send an email notifying you about the change.';
    }

    # Success
    return '';
}

1;
