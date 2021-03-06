Logging
==============================

We are transitioning to using Log4perl for all logging.  The code still has lots of 'say STDERR' statements, but these
should be gradually replaced with the below logging calls.  New code should use the log4perl logging.

The basic idea of log4perl is to send every log message with a category and priority and to associate those
categories / priorities to appenders in a configuration file.

The mc log4perl configuration file is in log4perl.conf, and the default just logs all messages of WARN or above
to STDERR:

```
log4perl.rootLogger = WARN, STDERR

log4perl.appender.STDERR = Log::Log4perl::Appender::Screen
log4perl.appender.STDERR.name = stderr
log4perl.appender.STDERR.stderr = 1
log4perl.appender.STDERR.layout = Log::Log4perl::Layout::PatternLayout
log4perl.appender.STDERR.layout.ConversionPattern = %d %c: %m%n

log4perl.oneMessagePerAppender = 1
```

The following log4perl calls are defined in and exported from MediaWords::CommonLibs:

```
FATAL ERROR WARN INFO DEBUG TRACE LOGDIE LOGWARN LOGCARP LOGCLUCK LOGCONFESS LOGCROAK
```

To log, just invoked the function for the appropriate logging level, for example:

```perl
if ( !$story_content )
{
    DEBUG( "SKIP - NO CONTENT" );
    return;
}
```

If called from MediaWords::TM::Mine, this will get printed by the default STDERR appender as:

```
2016/04/13 13:59:35 MediaWords.CM.Mine: SKIP - NO CONTENT
```

To see more info from specific categories, add lines like the following to the log4perl.conf file:

```
log4perl.logger.MediaWords.CM.Mine = DEBUG, STDERR
```

Keep in mind that perl will evaluate any expression passed as argument to a logging call.  But log4perl supports
passing subs as arguments, so for calls that use anything other than a constant string, you should use a sub:

```
INFO( sub { "merging " . scalar( @{ $archive_is_stories } ) . " archive.is stories" } )
```

To set the category of a script or test to something other than `main`, use a `package` statement in the script.
For example the following package statement at the top of script/mediawords_web_store.pl causes all log statements
in the script to be logged under the category `script.mediawords_web_store`.

```
package script::mediawords_web_store;
```

For convention, use a `script::*` package for scripts and a `t::*` package for tests.

Use the following guidelines when deciding which logging level to use:

TRACE - detailed trace as low as line by line level, very noisy and generally useful only if a specific bit of code is giving trouble

DEBUG - traces basic operation of the code, pretty noisy but generally useful for following the basic flow of the code

INFO - stuff I would want to know even if not actively following that part of the code

WARN - something is off, equivalent of a perl warn(), but not worth directly notifying us

ERROR - something is off, and we should be notified of it

FATAL / LOGDIE - fatal error, program should die and we should be notified
