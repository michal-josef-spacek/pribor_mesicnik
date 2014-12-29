#!/usr/bin/env perl
# Copyright 2014 Michal Špaček <tupinek@gmail.com>

# Pragmas.
use strict;
use warnings;

# Modules.
use Database::DumpTruck;
use Digest::MD5;
use Encode qw(decode_utf8 encode_utf8);
use English;
use File::Temp qw(tempfile);
use LWP::UserAgent;
use URI;
use Web::Scraper;

# Constants.
my $DATE_WORD_HR = {
	decode_utf8('leden') => 1,
	decode_utf8('únor') => 2,
	decode_utf8('březen') => 3,
	decode_utf8('duben') => 4,
	decode_utf8('květen') => 5,
	decode_utf8('červen') => 6,
	decode_utf8('červenec') => 7,
	decode_utf8('srpen') => 8,
	decode_utf8('září') => 9,
	decode_utf8('říjen') => 10,
	decode_utf8('listopad') => 11,
	decode_utf8('prosinec') => 12,
};

# Don't buffer.
$OUTPUT_AUTOFLUSH = 1;

# URI of service.
my $base_uri = URI->new('http://www.pribor.cz/www/cz/mesicnik-mesta-pribor/');

# Open a database handle.
my $dt = Database::DumpTruck->new({
	'dbname' => 'data.sqlite',
	'table' => 'data',
});

# Create a user agent object.
my $ua = LWP::UserAgent->new(
	'agent' => 'Mozilla/5.0',
);

# Get pages.
my @pages = get_pages($base_uri);

# Get all items.
foreach my $page (@pages) {
	print "$page\n";
	foreach my $item_hr (get_items($page)) {
		my $title = decode_utf8($item_hr->{'title'});
		print '- '.encode_utf8($title)."\n";
		my ($month_word, $year) = $title =~ m/(\w+)\s+(\d+)\s*$/ms;
		my $month = $DATE_WORD_HR->{$month_word};
		my $md5 = md5($item_hr->{'href'});
		$dt->insert({
			'Year' => $year,
			'PDF_link' => $item_hr->{'href'},
			'Month' => $month,
			'MD5' => $md5,
		});
	}
}

# Get content.
sub get_content {
	my $uri = shift;
	my $get = $ua->get($uri->as_string);
	my $data;
	if ($get->is_success) {
		$data = $get->content;
	} else {
		die "Cannot GET '".$uri->as_string." page.";
	}
	return $data;
}

# Get items.
sub get_items {
	my $page_uri = shift;
	my $content = get_content($base_uri);
	my $def = scraper {
		process '//div[@class="pr_pad content"]/div[@class="attachments"]/div[@class="attachment"]',
			'items[]' => scraper {

			process '//a[2]', 'title' => 'TEXT';
			process '//a[2]', 'href' => '@href';
			return;
		};
		return;
	};
	my $ret_hr = $def->scrape($content);
	return @{$ret_hr->{'items'}};
}

# Get pages.
sub get_pages {
	my $base_uri = shift;
	my $content = get_content($base_uri);
	my $def = scraper {
		process '//ul[@class="articles_list"]/li', 'pages[]' => scraper {
			process '//a', 'page' => 'TEXT';
			process '//a', 'url' => '@href';
			return; 
		};
        	return; 
	};      
	my $ret_hr = $def->scrape($content);
	return map { $_->{'url'} } @{$ret_hr->{'pages'}};
}
	
# Get link and compute MD5 sum.
sub md5 {
	my $link = shift;
	my (undef, $temp_file) = tempfile();
	my $get = $ua->get($link, ':content_file' => $temp_file);
	my $md5_sum;
	if ($get->is_success) {
		my $md5 = Digest::MD5->new;
		open my $temp_fh, '<', $temp_file;
		$md5->addfile($temp_fh);
		$md5_sum = $md5->hexdigest;
		close $temp_fh;
		unlink $temp_file;
	}
	return $md5_sum;
}
