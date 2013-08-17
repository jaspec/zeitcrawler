#!/usr/bin/perl


###			ZEITCRAWLER v1.3		###
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

use Getopt::Long;
use LWP::UserAgent;
use base 'HTTP::Message';
require Compress::Zlib;
use utf8;
use open ':encoding(utf8)';
use Digest::MD5 qw(md5_base64);

use Try::Tiny;


### TODO :
# add arguments
# add subroutines
# "just process list" mode ?
# something else as LWP ?


# command-line options
my ($help, $timeout, $number, $sleep, $all_links, $no_new_links);
usage() if ( @ARGV < 1
	or ! GetOptions ('help|h' => \$help, 'timeout|t=i' => \$timeout, 'number|n=i' => \$number, 'sleep|s=i' => \$sleep,  'all|a' => \$all_links, 'no-new-links' => \$no_new_links)
	or defined $help
	or ( (defined $all_links) && (defined $number) )
        or ( (! defined $all_links) && (! defined $number) )
);

sub usage {
	print "Unknown option: @_\n" if ( @_ );
	print "Usage: perl zeitcrawler.pl [--help|-h] [--number|-n] [--timeout|-t] [--sleep|-s] [--all-links|-a] [--no-new-links]\n\n";
	print "number: \n";
	print "timeout: \n";
	print "sleep: \n";
	print "all-links: \n";
	print "no-new-links: \n\n";
	exit;
}


# Init
my $recup = "index";

## DEFAULTS

# timeout
unless (defined $timeout) {
    $timeout = 12;
}

# sleep
unless (defined $sleep) {
$sleep = 5;
}

# md5 length
my $md5length = 10;


# configuring the LWP agent
my $ua = LWP::UserAgent->new;
my $can_accept = HTTP::Message::decodable;
$ua->agent("ZeitCrawler/1.3 +https://code.google.com/p/zeitcrawler/");
$ua->timeout($timeout);

my $runs = 1;
my $successful = 0;
my ($url, $urlcorr, $block, $seite, $n, @text, $titel, $excerpt, $info, $autor, $datum, @reihe, $link, @links, @temp, %seen, @buffer, $q, $md5);


##Loading...
print "Initialization...\n";

my $done_md5_file = 'ZEIT_list_done_md5';
my %done_md5;
if (-e $done_md5_file) {
	open (my $done_md5_read, '<', $done_md5_file) or die "Cannot open list-done-md5 file: $!\n";
	while (<$done_md5_read>) {
		chomp;
		$done_md5{$_} = ();
	}
	close ($done_md5_read) or die;
}

my $links_file = 'ZEIT_list_todo';
my @liste;
if (-e $links_file) {
	open (my $links, '<', $links_file) or die "Cannot open list-todo file: $!\n";
	my $i = 0;
	while (<$links>) {
		chomp;
                my $templink = $_;
		$templink =~ s/\/komplettansicht.*$//;
		$templink =~ s/\/+$//;
                try {
		    $md5 = substr(md5_base64($templink), 0, $md5length);
		    unless (exists $done_md5{$md5}) {
                        push (@liste, $templink);
		    }
                }
                catch {
                    print "Problem: " . $_ . "--" .  "by URL" . $templink . "\n";
                }
	}
	%seen = ();
	@liste = grep { ! $seen{ $_ }++ } @liste; # remove duplicates (fast)
	close ($links) or die;
}

open (my $output, '>>', 'ZEIT_flatfile') or die "Cannot open output file: $!\n";
open (my $log, '>>', 'ZEIT_log') or die "Cannot open log file: $!\n";
open (my $done, '>>', 'ZEIT_list_done') or die "Cannot open list-done file: $!\n";


# Begin of the main loop

if (defined $all_links) {
    $number = scalar(@liste);
}

print "run -- list -- buffer\n";
while ($runs <= $number) {

  if (@liste) {
        $url = shift(@liste);
        # a wide shot... but correct if the list was generated using the "make list" tool
        # if ($url !~ m/^http:\/\/www.zeit.de\//) {
	    $urlcorr = "http://www.zeit.de/" . $url . "/komplettansicht";
        #}
        # no $urlcorr if it's not the case
        #else {
        #    $urlcorr = $url;
        #}
  }
  else {
	$url = $recup;
	# quick hack
	$urlcorr = "http://www.zeit.de/index";
  }

  $md5 = substr(md5_base64($url), 0, $md5length);
  $done_md5{$md5} = ();
  print $done $url, "\n";

  # Change output frequency here :
  if ($runs % 10 == 0) {
	print $runs, "\t"; print scalar (@liste), "\t"; print scalar (@buffer), "\n";
  }

  print $log "$runs\t"; print $log scalar (@liste), "\n";
  @text = ();



  # Fetch the page (re-encoding not always necessary)
  my $request = HTTP::Request->new(GET => $urlcorr);
  $request->header(
	'Accept' => 'text/html',
	'Accept-Encoding' => $can_accept,
  );
  my $result = $ua->request($request);
  if ($result->is_success) {
      print $log "$url\tOK\n";
      $seite = $result->decoded_content; #(charset => 'none')
  }
  else {
      print $log "$urlcorr\tError\n";
      print $log $result->status_line, "\n";
      $runs++;
      next;
  }


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
			unless ($link =~ m/#|-box-|xml|bildergalerie|bg-|Spiele|quiz|themen|index|video\/|administratives\//o) { #replacement for unless ( ($link =~ m/#/) || ($link =~ m/-box-/) || ($link =~ m/xml/) || ($link =~ m/bildergalerie/) || ($link =~ m/bg-/) || ($link =~ m/Spiele/) || ($link =~ m/quiz/) || ($link =~ m/themen/) || ($link =~ m/index/) ) {
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
		$md5 = substr(md5_base64($n), 0, $md5length);
		unless (exists $done_md5{$md5}) {
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
		$md5 = substr(md5_base64($n), 0, $md5length);
		unless (exists $done_md5{$md5}) {
		push (@liste, $n);
		}
	}
	@buffer = ();
  }

  %seen = ();
  @liste = grep { ! $seen{ $_ }++ } @liste; # remove duplicates (fast)


  unless ($url eq $recup) { # do not process the index page
  # Extraction of metadata
  # All this part is based on regular expressions, which is not recommended when crawling in the wild.

  @temp = split ("<!--AB HIER IHR CONTENT-->", $seite);
  $seite = $temp[1];

  if ($seite =~ m/class="newcomments zeitkommentare">/o) {
	@temp = split ("<div id=\"comments\" class=\"newcomments zeitkommentare\">", $seite);
  }
  else {
	@temp = split ("<div id=\"informatives\"", $seite);
  }

  $seite = $temp[0];
  $info = $temp[1];

  { no warnings 'uninitialized'; # do not display any warning of the selection is empty

  $seite =~ m/<span class="title">(.+?)<\/span>/o;
  $titel = $1;
  $titel = "Titel: " . $titel;
  push (@text, $titel);

  if ($seite =~ m/<p class="excerpt">(.+?)<\/p>/o) {
        $excerpt = $1;
  }
  else {
      $excerpt = "";
  }
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
  splice (@reihe, 0, 1); # shift ?

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
        if ( ($block =~ m/Ergänzend zur Textversion bieten wir Ihnen/o) || ($block =~ m/Die Nutzung ist ausschließlich in den Grenzen/o) ) {
		$block = ();
	}
	if (($block =~ m/zeit.de\/musik/o) || ($block =~ m/zeit.de\/audio/o) || ($block =~ m/\[weiter\?\]/o) || ($block =~ m/Lesen Sie hier mehr aus dem Ressort/o)) {
		$block = ();
	}
	push (@text, $block) if defined ($block);
  }

  # Does not print out an empty text
  if (scalar(@text) > 10) {
	foreach $n (@text) {
		print $output "$n\n";
	}
	print $output "-----\n";
  }
  } # end of 'do not display any warning if the selection is empty'
  } # end of 'do not process the index page'

  if ( (scalar @liste == 0) && (@buffer) ) {
	%seen = ();
	@buffer = grep { ! $seen{ $_ }++ } @buffer; # remove duplicates (fast)
	foreach $n (@buffer) {
		$md5 = substr(md5_base64($n), 0, $md5length);
		unless (exists $done_md5{$md5}) {
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

  # Sleep between two page views
  select(undef, undef, undef, $sleep);
}

# End of processing, saving lists 
close ($output);
close ($done);

open (my $done_md5_write, '>', $done_md5_file) or die "Cannot open list-done-md5 file (no write access ?) : $!\n";
print $done_md5_write join("\n", keys %done_md5);
close ($done_md5_write);

open (my $todo_write, '>', $links_file) or die "Cannot open list-todo file (no write access ?) : $!\n";
if (@buffer) {
	push (@liste, @buffer);
	print "Buffer stored\n";
}
%seen = ();
@liste = grep { ! $seen{ $_ }++ } @liste; # remove duplicates (fast)
print $todo_write join("\n", @liste);
close ($todo_write);

print $log "***************\n";
close ($log);
