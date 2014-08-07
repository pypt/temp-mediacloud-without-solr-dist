# 1. 
# 2. This file lists *direct* Perl module dependencies of Media Cloud.
# 3. 
# 4. See:
# 5. 
# 6.     doc/carton.txt
# 7. 
# 8. for instructions on how to add a new Perl module dependency.
# 9. 
requires 'Algorithm::FeatureSelection';
requires 'Archive::Zip';
requires 'Array::Compare';
requires 'Cache::FastMmap';
requires 'Carton::CLI';
requires 'Catalyst', '5.90030';
requires 'Catalyst::Action::RenderView';
requires 'Catalyst::Action::REST';
requires 'Catalyst::Authentication::User::Hash';
requires 'Catalyst::Controller::HTML::FormFu';
requires 'Catalyst::Controller::REST';
requires 'Catalyst::Plugin::Authorization::ACL';
requires 'Catalyst::Plugin::ConfigLoader';
requires 'Catalyst::Plugin::I18N';
requires 'Catalyst::Plugin::Session::Store::FastMmap';
requires 'Catalyst::Plugin::Session::Store::File';
requires 'Catalyst::Plugin::StackTrace';
requires 'Catalyst::Plugin::Static::Simple';
requires 'Catalyst::Plugin::Unicode';
requires 'Catalyst::Runtime', '5.90030';
requires 'Catalyst::View::TT';
requires 'CGI';
requires 'CHI';
requires 'Class::CSV';
requires 'Class::Std';
requires 'Color::Mix';
requires 'Config::Any';
requires 'Crypt::SaltedHash';
requires 'Data::Dumper';
requires 'Data::Page';
requires 'Data::Serializer';
requires 'Data::Sorting';
requires 'Data::Structure::Util';
requires 'Data::Validate::URI';
requires 'DateTime::Format::Pg';
requires 'DBD::Pg', '2.19.3';
requires 'DBIx::Class::Schema';
requires 'DBIx::Simple';
requires 'Devel::Cover', '1.15'; #make sure Devel::Cover is current (version newer than 1.15 should be ok too
requires 'Devel::Cover::Report::Coveralls', '0.08';
requires 'Devel::NYTProf';
requires 'Dir::Self';
requires 'Domain::PublicSuffix';
requires 'Email::MIME';
requires 'Email::Sender::Simple';
requires 'Encode::HanConvert';
requires 'ExtUtils::MakeMaker';
requires 'FCGI';
requires 'FCGI::ProcManager';
requires 'Feed::Find';
requires 'File::Touch';
requires 'forks', '0.34';
requires 'Gearman::JobScheduler', '0.16';
requires 'Graph';
requires 'GraphViz';
requires 'HTML::CruftText', '0.02';
requires 'HTML::Entities';
requires 'HTML::FormFu';
requires 'HTML::FormFu::Element::reCAPTCHA';
requires 'HTML::LinkExtractor';
requires 'HTML::Strip';
requires 'HTML::TagCloud';
requires 'HTML::TreeBuilder::LibXML';
requires 'Inline';
requires 'Inline::Java';
requires 'Inline::Python';
requires 'IO::Compress::Bzip2';
requires 'IO::Compress::Gzip';
requires 'IPC::Run3';
requires 'IPC::System::Simple';
requires 'JSON';
requires 'Lingua::Identify::CLD', '0.08';
requires 'Lingua::Sentence';
requires 'Lingua::Stem';
requires 'Lingua::Stem::Snowball';
requires 'Lingua::Stem::Snowball::Lt', '0.02';
requires 'Lingua::StopWords';
requires 'Lingua::ZH::WordSegmenter';
requires 'List::Compare';
requires 'List::Member';
requires 'List::MoreUtils';
requires 'List::Pairwise';
requires 'List::Uniq';
requires 'Locale::Country::Multilingual';
requires 'Log::Log4perl';
requires 'LWP::Protocol::https';
requires 'Math::Random';
requires 'Memoize';
requires 'Modern::Perl', '1.20121103';
requires 'Module::Install';
requires 'Module::Pluggable::Object';
requires 'MongoDB', '0.704.1.0';
requires 'Moose', '== 2.1005';
requires 'namespace::autoclean';
requires 'Net::Amazon::S3';
requires 'Net::Calais';
requires 'Net::IP';
requires 'Parallel::Fork::BossWorkerAsync';
requires 'Parallel::ForkManager';
requires 'PDL';
requires 'Perl::Tidy', '20140328';
requires 'RDF::Simple::Parser';
requires 'Readonly';
requires 'Readonly::XS';
requires 'Regexp::Common';
requires 'Regexp::Common::time';
requires 'Set::Jaccard::SimilarityCoefficient';
requires 'Set::Scalar';
requires 'Smart::Comments';
requires 'Statistics::Basic';
requires 'Sys::RunAlone';
requires 'Template';
requires 'Term::Prompt';
requires 'Test::Differences';
requires 'Test::NoWarnings';
requires 'Test::Strict';
requires 'Text::CSV';
requires 'Text::Iconv';
requires 'Text::Similarity::Overlaps';
requires 'Text::Trim';
requires 'Tie::Cache';
requires 'URI::Find';
requires 'WebService::Google::Language';
requires 'XML::FeedPP';
requires 'XML::LibXML';
requires 'XML::Simple';
requires 'YAML::Syck';
