#!/usr/bin/perl


###			ZEITCRAWLER v1.0.1		###
###		http://code.google.com/p/zeitcrawler/ 		###

###	This script is brought to you by Adrien Barbaresi.
###	It is freely available under the GNU GPL v3 license (http://www.gnu.org/licenses/gpl.html).
###	Five files are generated by the program (some are needed to go on crawling).

###	The crawler does not support multi-threading, as this may not be considered a fair use.
###	The gathered texts are for personal (or academic) use only, you cannot republish them.
###	The cases which allow for a free use of the texts are listed on this page (in German) :
###	http://www.zeitverlag.de/presse/rechte-und-lizenzen/freie-nutzung/


## Use : change the number of pages crawled to fit your needs (the program supports successive executions).
## Execute the file without arguments.


use strict;
use warnings;
#use locale;
use LWP::Simple;
use utf8;
use open ':encoding(utf8)';
use String::CRC32; # probably needs to be installed, e.g. using the CPAN console or directly with the Debian/Ubuntu package libstring-crc32-perl



# Init
my $recup = "index";

# Change number of pages crawled at a time here
my $number = 1000;

my $runs = 1;
my ($url, $urlcorr, $block, $seite, $n, @text, $titel, $excerpt, $info, $autor, $datum, @reihe, $link, @links, @temp, @done, $line, %seen);
my (@buffer, $q);
my ($crc, @done_crc, $links_crc);

my $output = ">>ZEIT_flatfile";
open (OUTPUT, $output) or die;
my $record = '>>ZEIT_log';
open (TRACE, $record) or die;
my $done = '>>ZEIT_list_done';
open (DONE, $done);

##Loading...
print "Initialisation...\n";

my $done_crc = 'ZEIT_list_done_crc';
my %done_crc;
if (-e $done_crc) {
open (DONE_CRC, $done_crc) or die;
$line = 0;
	while (<DONE_CRC>) {
	chomp;
	$done_crc{$_}++;
	$done_crc[$line] = $_;
	$line++;
	}
close (DONE_CRC) or die;
}

my $links = 'ZEIT_list_todo';
my @liste;
if (-e $links) {
open (LINKS, $links) or die;
my $i = 0;
	while (<LINKS>) {
	chomp;
	$_ =~ s/\/komplettansicht.*$//;
	$_ =~ s/\/+$//;
	$crc = crc32($_);
	unless (exists $done_crc{$crc}) {
	push (@liste, $_);
	}
	}
%seen = ();
@liste = grep { ! $seen{ $_ }++ } @liste; # remove duplicates (fast)
close (LINKS) or die;
}


# Begin of the main loop

print "run -- list -- buffer\n";
while ($runs <= $number) {

if (@liste) {
$url = splice (@liste, 0, 1);
}
else {
$url = $recup;
}

push (@done_crc, crc32($url));
$done_crc{crc32($url)}++;
print DONE $url, "\n";

# Change output frequency here :
if ($runs%10 == 0) {
print $runs, "\t"; print scalar (@liste), "\t"; print scalar (@buffer), "\n";
}

print TRACE "$runs\t"; print TRACE scalar (@liste), "\n";
print TRACE "$url\n";
@text = ();



# Fetch the page (re-encoding not always necessary)
$urlcorr = "http://www.zeit.de/" . $url . "/komplettansicht";
$seite = get $urlcorr;


# Links
@links = ();
@temp = split ("<a", $seite);
foreach $n (@temp) {
if ($n =~ m/(http:\/\/www\.zeit\.de\/)(.+?)(")/o) {
	$link = $2;
	if ( $link =~ m/\/[0-9]{4}[\/-][0-9]{2}\//o ) { # replacement for if ( ($link =~ m/[0-9]{4}-[0-9]{2}/) || ($link =~ m/[0-9]{4}\/[0-9]{2}/) ) {
		$link =~ s/seite-[0-9]//o;
		$link =~ s/seite-NaN//o;
			if ($link =~ m/\?/o) {
			$link =~ m/(.+?)(\?)/o;
			$link = $1;
			}
		unless ($link =~ m/#|-box-|xml|bildergalerie|bg-|Spiele|quiz|themen|index/o) { #replacement for unless ( ($link =~ m/#/) || ($link =~ m/-box-/) || ($link =~ m/xml/) || ($link =~ m/bildergalerie/) || ($link =~ m/bg-/) || ($link =~ m/Spiele/) || ($link =~ m/quiz/) || ($link =~ m/themen/) || ($link =~ m/index/) ) {
		# Alternative list : unless (($link =~ m/angebote/) || ($link =~ m/\?/) || ($link =~ m/hilfe/) || ($link =~ m/studium/) || ($link =~ m/newsletter/) || ($link =~ m/spiele/) || ($link =~ m/zuender/) || ($link =~ m/bildergalerie/) || ($link =~ m/bg-/) || ($link =~ m/quiz/) || ($link =~ m/rezept/) || ($link =~ m/siebeck/)) {
			$link =~ s/\/komplettansicht$//og; # $ added (faster)
			$link =~ s/\/+$//og;
			$link =~ s/\/[0-9]+$//og; # $ added (did not work otherwise)
			push (@links, $link);
		#}
		}
	}
}
}

%seen = ();
@links = grep { ! $seen{ $_ }++ } @links; # remove duplicates (fast)

# Storing and buffering links
# The use of a buffer saves memory and processing time (especially by frequently occurring links)
$q=0;
foreach $n (@links) {
	if ($q >= 4) {
	push (@buffer, $n);
	}
	else {
		$crc = crc32($n);
		unless (exists $done_crc{$crc}) {
		push (@liste, $n);
		}
	}
	$q++;
}


# Buffer control
if (scalar @buffer >= 500) {
	%seen = ();
	@buffer = grep { ! $seen{ $_ }++ } @buffer; # remove duplicates (fast)
	foreach $n (@buffer) {
		$crc = crc32($n);
		unless (exists $done_crc{$crc}) {
		push (@liste, $n);
		}
	}
	@buffer = ();
}

%seen = ();
@liste = grep { ! $seen{ $_ }++ } @liste; # remove duplicates (fast)


# Extraction of metadata
# All this part is based on regular expressions, which is not recommended when crawling in the wild.

@temp = split ("<!--AB HIER IHR CONTENT-->", $seite);
$seite = $temp[1];

if ($seite =~ m/class="newcomments zeitkommentare">/o) {
	@temp = split ("<div id=\"comments\" class=\"newcomments zeitkommentare\">", $seite);
	#@temp = split ("<div id=\"informatives\">", $seite);
}
else {
	@temp = split ("<div id=\"informatives\">", $seite);
}

$seite = $temp[0];
$info = $temp[1];

$seite =~ m/<span class="title">(.+?)<\/span>/o;
$titel = $1;
$titel = "Titel: " . $titel;
push (@text, $titel);

$seite =~ m/<p class="excerpt">(.+?)<\/p>/o;
$excerpt = $1;
$excerpt = "Excerpt: " . $excerpt;
push (@text, $excerpt);

if ($info =~ m/<li itemprop="author" content="([A-Za-zÄÖÜäöüß ]+)"/) {
	$autor = $1;
}
else {
	if ($info =~ m/<strong>Von<\/strong>([A-Za-zÄÖÜäöüß ]+)<\/li>/o) {
	$autor = $1;
	}
	else {
		$autor = "";
	}
}
$autor = "Autor: " . $autor;
push (@text, $autor);

$info =~ m/<li itemprop="datePublished" content="([0-9]+\.[0-9]+\.[0-9]+)/o;
$datum = $1;
$datum = "Datum: " . $datum;
push (@text, $datum);

push (@text, "url: $url\n");


# Extraction of the text itself
# Using regular expressions, there might be a more efficient way to do this.

if ($seite =~ m/<div class="block">/o) {
$seite =~ s/.+<div class="block">//o;
}
else {
$seite =~ s/.+class="article">//o;
}
@reihe = split ("<p>", $seite);
splice (@reihe,0,1);

foreach $block (@reihe) {
	#next if $block eq "</p>";
	$block =~ s/<p class="caption">.+?<\/p>//o;
	$block =~ s/\n+//og;
	$block =~ m/[A-Z].+?<\/p>/o;
	$block = $&;
	$block =~ s/<.+?>//og;
	$block =~ s/^\s+//og; # moved because of execution time
	$block =~ s/^<li.+?$//ogs;
	$block =~ s/\s+/ /og;
		if (($block =~ m/zeit.de\/musik/o) || ($block =~ m/zeit.de\/audio/o) || ($block =~ m/\[weiter\?\]/o) || ($block =~ m/Lesen Sie hier mehr aus dem Ressort/o)) {
		$block = ();
		}
	push (@text, $block) if defined ($block);
	}

# Does not print out an empty text
if (scalar(@text) > 5) {
	foreach $n (@text) {
		print OUTPUT "$n\n";
	}
	print OUTPUT "-----\n";
}

if ( (scalar @liste == 0) && (@buffer) ) {
	%seen = ();
	@buffer = grep { ! $seen{ $_ }++ } @buffer; # remove duplicates (fast)
	foreach $n (@buffer) {
		$crc = crc32($n);
		unless (exists $done_crc{$crc}) {
		push (@liste, $n);
		}
	}
	@buffer = ();
	%seen = ();
	@liste = grep { ! $seen{ $_ }++ } @liste; # remove duplicates (fast)
}

if ( (scalar (@liste) == 0) && (scalar (@buffer) == 0) ) {
last;
}

$runs++;
}

# End of processing, saving lists 
close (OUTPUT);
close (DONE);

$done_crc = '>ZEIT_list_done_crc';
open (DONE_CRC, $done_crc);
foreach $n (@done_crc) {
print DONE_CRC "$n\n";
}
close (DONE_CRC);

$links = '>ZEIT_list_todo';
open (LINKS, $links) or die;
if (@buffer) {
	push (@liste, @buffer);
	print "Buffer stored\n";
}
%seen = ();
@liste = grep { ! $seen{ $_ }++ } @liste; # remove duplicates (fast)
foreach $n (@liste) {
print LINKS "$n\n";
}
close (LINKS);

print TRACE "***************\n";
close (TRACE);
