#!/usr/bin/perl
#
# Some test strings copied from Wikipedia (CC-BY-SA, http://creativecommons.org/licenses/by-sa/3.0/).
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Readonly;

use Test::NoWarnings;
use Test::More tests => 1 + 1;
use utf8;

# Test::More UTF-8 output
my $builder = Test::More->builder;
binmode $builder->output,         ":utf8";
binmode $builder->failure_output, ":utf8";
binmode $builder->todo_output,    ":utf8";

use MediaWords::Languages::ru;
use Data::Dumper;

my $test_string;
my $expected_sentences;

my $lang = MediaWords::Languages::ru->new();

#
# Simple paragraph + some non-breakable abbreviations
#
$test_string = <<'QUOTE';
Новозеландцы пять раз признавались командой года по версии IRB и являются лидером по количеству набранных
очков и единственным коллективом в международном регби, имеющим положительный баланс встреч со всеми своими
соперниками. «Олл Блэкс» удерживали первую строчку в рейтинге сборных Международного совета регби дольше,
чем все остальные команды вместе взятые. За последние сто лет новозеландцы уступали лишь шести национальным
командам (Австралия, Англия, Родезия, Уэльс, Франция и ЮАР). Также в своём активе победу над «чёрными» имеют
сборная Британских островов (англ.)русск. и сборная мира (англ.)русск., которые не являются официальными
членами IRB. Более 75 % матчей сборной с 1903 года завершались победой «Олл Блэкс» — по этому показателю
национальная команда превосходит все остальные.
QUOTE

$expected_sentences = [
'Новозеландцы пять раз признавались командой года по версии IRB и являются лидером по количеству набранных очков и единственным коллективом в международном регби, имеющим положительный баланс встреч со всеми своими соперниками.',
'«Олл Блэкс» удерживали первую строчку в рейтинге сборных Международного совета регби дольше, чем все остальные команды вместе взятые.',
'За последние сто лет новозеландцы уступали лишь шести национальным командам (Австралия, Англия, Родезия, Уэльс, Франция и ЮАР).',
'Также в своём активе победу над «чёрными» имеют сборная Британских островов (англ.)русск. и сборная мира (англ.)русск., которые не являются официальными членами IRB.',
'Более 75 % матчей сборной с 1903 года завершались победой «Олл Блэкс» — по этому показателю национальная команда превосходит все остальные.'
];

{
    is( join( '||', @{ $lang->get_sentences( $test_string ) } ), join( '||', @{ $expected_sentences } ), "sentence_split" );
}
