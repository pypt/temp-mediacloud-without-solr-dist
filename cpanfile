#
# This file lists *direct* Perl module dependencies of Media Cloud.
#
# See:
#
#     doc/carton.txt
#
# for instructions on how to add a new Perl module dependency.
#
requires 'Algorithm::FeatureSelection';
requires 'Archive::Zip';
requires 'Array::Compare';
requires 'BerkeleyDB';
requires 'Cache::FastMmap';
requires 'Carton::CLI';
requires 'Catalyst::Authentication::User::Hash';
requires 'Catalyst::Controller::HTML::FormFu';
requires 'Catalyst::Controller::REST';
requires 'Catalyst::Plugin::Authorization::ACL';
requires 'Catalyst::Plugin::I18N';
requires 'Catalyst::Plugin::Session::Store::FastMmap';
requires 'Catalyst::Plugin::StackTrace';
requires 'Catalyst::Plugin::Static::Simple';
requires 'Catalyst::Plugin::Unicode';
requires 'Catalyst::Runtime';
requires 'CHI';
requires 'Class::CSV';
requires 'Class::Std';
requires 'Color::Mix';
requires 'Config::Any';
requires 'Crypt::SaltedHash';
requires 'Data::Dumper';
requires 'Data::Page';
requires 'Data::Serializer';
requires 'Data::Validate::URI';
requires 'DateTime::Format::Pg';
requires 'DBD::Pg', '2.19.3';
requires 'DBIx::Class::Schema';
requires 'DBIx::Simple';
requires 'Devel::NYTProf';
requires 'Devel::SizeMe';
requires 'Dir::Self';
requires 'Domain::PublicSuffix';
requires 'Email::MIME';
requires 'Email::Sender::Simple';
requires 'Encode::HanConvert';
requires 'FCGI::ProcManager';
requires 'Feed::Find';
requires 'File::Touch';
requires 'Graph';
requires 'Graph::Layout::Aesthetic';
requires 'GraphViz';
requires 'HTML::CruftText';
requires 'HTML::Entities';
requires 'HTML::FormatText';
requires 'HTML::FormFu';
requires 'HTML::LinkExtractor';
requires 'HTML::Strip';
requires 'HTML::TagCloud';
requires 'HTML::TreeBuilder::LibXML';
requires 'IPC::Run3';
requires 'IPC::System::Simple';
requires 'Lingua::Identify::CLD';
requires 'Lingua::Sentence';
requires 'Lingua::Stem';
requires 'Lingua::Stem::Snowball';  # FIXME replace with modified version
requires 'Lingua::StopWords';
requires 'Lingua::ZH::WordSegmenter';
requires 'List::Compare';
requires 'List::Member';
requires 'List::MoreUtils';
requires 'List::Pairwise';
requires 'List::Uniq';
requires 'Locale::Country::Multilingual';
requires 'Math::Random';
requires 'Modern::Perl';
requires 'MongoDB', '0.700.0';
requires 'namespace::autoclean';
requires 'Net::Calais';
requires 'Parallel::ForkManager';
requires 'PDL';
requires 'Perl::Tidy';
requires 'RDF::Simple::Parser';
requires 'Readonly';
requires 'Regexp::Common';
requires 'Smart::Comments';
requires 'Term::Prompt';
requires 'Test::Differences';
requires 'Test::NoWarnings';
requires 'Test::Strict';
requires 'Text::Iconv';
requires 'Text::MediawikiFormat';
requires 'Text::Ngrams';
requires 'Text::Similarity::Overlaps';
requires 'Text::Trim';
requires 'WebService::Google::Language';
requires 'XML::FeedPP';
requires 'XML::LibXML';
requires 'XML::Simple';
requires 'YAML::Syck';
