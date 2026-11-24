package Plugins::RadioStations::NativeEditor;
# Derived from Slim::Plugin::Favorites::Plugin (LMS 9.0.3).
# Logitech Media Server Copyright 2005-2024 Logitech.
# Lyrion Music Server Copyright 2024 Lyrion Community.
# SPDX-License-Identifier: GPL-2.0-only
# Native actions and session flow, isolated to Radio Stations storage.
use strict;
use Tie::Cache::LRU;
use Slim::Utils::Log;
use Slim::Utils::Strings qw(string cstring);
use Slim::Music::Info;
use Slim::Web::XMLBrowser;
use Plugins::RadioStations::EditorStore;
use URI::Escape qw(uri_escape_utf8);
my $log=logger('plugin.radiostations');
my $nextSession=time();
tie my %sessions,'Tie::Cache::LRU',32;
sub indexHandler {
	my $client = shift;
	my $params = shift;

	# Debug:
	#for my $key (keys %$params) {
	#	print "Key: $key, Val: ".$params->{$key}."\n";
	#}

	my $sessId=$params->{sess};
    my $session=$sessId && $sessions{$sessId};
    if (!$session) {
        if ($sessId) {
            delete @{$params}{qw(action newentry insert forgetdelete)};
            $params->{errormsg}=cstring($client,'PLUGIN_RADIOSTATIONS_EDITOR_EXPIRED');
        }
        $sessId=++$nextSession;
        $session={opml=>Plugins::RadioStations::EditorStore->new(),autosave=>1};
    }
    my $opml=$session->{opml};
    my $deleted=$session->{deleted};
    my $autosave=1;
    my ($edit,$changed);
    if (($params->{action} || '') =~ /^(?:edit|editset|delete|move|moveup|movedown)$/ &&
        (!defined($params->{index}) || $params->{index} !~ /^\d+$/ || $params->{index} >= @{$opml->toplevel})) {
        delete $params->{action};
        $params->{errormsg}=cstring($client,'PLUGIN_RADIOSTATIONS_EDIT_MISSING');
    }
    delete $params->{to} if defined($params->{to}) && $params->{to} !~ /^\d+$/;
    # This editor is restricted to the independent flat radio list.
    delete @{$params}{qw(new newlevel load loadfile save savefile savechanged import importfile title)};
    delete @{$params}{qw(into tolevel)};
    if (($params->{action} || '') eq 'editset') {
        $params->{fetched}=1;
        $params->{fetchedtype}='audio/mpeg';
    }

    # get the level to operate on - this is the level containing the index if action is set, otherwise the level specified by index
	my ($level, $indexLevel, @indexPrefix) = $opml->level($params->{'index'}, defined $params->{'action'});

	if (!defined $level || $params->{'action'} =~ /^(?:play|add|insert)/) {

		# favorites editor cannot follow remote links, so pass through to xmlbrowser as index does not appear to be edittable
		# also pass through play/add to reuse xmlbrowser handling of playall etc
		main::INFOLOG && $log->info("passing through to xmlbrowser");

		return Slim::Web::XMLBrowser->handleWebIndex( {
			client => $client,
			feed   => $opml->xmlbrowser,
			args   => [$client, $params, @_],
		} );
	}

	my $favs;
	if (my $action = $params->{'action'}) {

		if ($action eq 'edit') {
			$edit = $indexLevel;
		}

		if ($action eq 'delete') {

			$deleted = splice @$level, $indexLevel, 1;

			$changed = 1;
		}

		if ($action eq 'move' && defined $params->{'to'} && $params->{'to'} < scalar @$level) {

			my $entry = splice @$level, $indexLevel, 1;

			splice @$level, $params->{'to'}, 0, $entry;

			$changed = 1;
		}

		if ($action eq 'move' && defined $params->{'tolevel'}) {

			my ($dest, undef, undef) = $opml->level($params->{'tolevel'});

			if ($dest) {
				push @$dest, splice @$level, $indexLevel, 1;
			}

			$changed = 1;
		}

		if ($action eq 'move' && defined $params->{'into'}) {

			if (my $dest = @$level[$params->{'into'}]->{'outline'}) {

				push @$dest, splice @$level, $indexLevel, 1;
			}

			$changed = 1;
		}

		if ($action eq 'movedown') {

			my $entry = splice @$level, $indexLevel, 1;

			splice @$level, $indexLevel + 1, 0, $entry;

			$changed = 1;
		}

		if ($action eq 'moveup' && $indexLevel > 0) {

			my $entry = splice @$level, $indexLevel, 1;

			splice @$level, $indexLevel - 1, 0, $entry;

			$changed = 1;
		}

		if ($action eq 'editset' && defined $params->{'index'}) {

			if ($params->{'cancel'} && $params->{'removeoncancel'}) {

				# cancel on a new item - remove it
				splice @$level, $indexLevel, 1;

			} elsif ($params->{'entrytitle'} && !$params->{'cancel'}) {

				# editted item - modify including possibly changing type
				my $entry = @$level[$indexLevel];

				$entry->{'text'} = $params->{'entrytitle'};
				$entry->{'icon'} = $params->{'entryicon'} if exists $params->{'entryicon'};

				if (defined $params->{'entryurl'} && $params->{'entryurl'} ne $entry->{'URL'}) {

					my $url = $params->{'entryurl'};

					if ($url !~ /^https?:/) {

						if ($url !~ /\.(xml|opml|rss)$/) {

							$entry->{'type'} = 'audio';

						} else {

							delete $entry->{'type'};
						}

					} elsif (!$params->{'fetched'}) {

						main::INFOLOG && $log->info("checking content type for $url");

						Slim::Networking::Async::HTTP->new()->send_request( {
							'request'     => HTTP::Request->new( GET => $url ),
							'onHeaders'   => \&asyncCBContentType,
							'onError'     => \&asyncCBContentTypeError,
							'passthrough' => [ $client, $params, @_ ],
						} );

						return;

					} else {

						my $mime = $params->{'fetchedtype'} || 'error';
						my $type = Slim::Music::Info::mimeToType($mime);

						if ($type) {

							main::INFOLOG && $log->info("got mime type $mime");

						} else {

							main::INFOLOG && $log->info("unknown mime type $mime, inferring from url");

							$type = Slim::Music::Info::typeFromPath($url);
						}

						if (Slim::Music::Info::isSong(undef, $type) || Slim::Music::Info::isPlaylist(undef, $type)) {

							main::INFOLOG && $log->info("content type $type - treating as audio");

							$entry->{'type'} = 'audio';

						} else {

							main::INFOLOG && $log->info("content type $type - treating as non audio");

							delete $entry->{'type'};
						}
					}

					$entry->{'URL'} = $url;
				}
			}

			$changed = 1;
		}

		if ($action eq 'favadd' && defined $params->{'index'} && $favs) {

			my $entry = @$level[$indexLevel];

			$favs->add( $entry->{'URL'}, $entry->{'text'}, $entry->{'type'}, $entry->{'parser'} );
		}

		if ($action eq 'favdel' && defined $params->{'index'} && $favs) {

			my $entry = @$level[$indexLevel];

			$favs->deleteUrl( $entry->{'URL'} );
		}
	}

	if ($params->{'forgetdelete'}) {

		$deleted = undef;
	}

	if ($params->{'insert'} && $deleted) {

		push @$level, $deleted;

		$deleted = undef;
		$changed = 1;
	}

	if ($params->{'newentry'}) {

		push @$level,{
			'text' => string('PLUGIN_FAVORITES_NAME'),
			'URL'  => string('PLUGIN_FAVORITES_URL'),
		};

		$edit = scalar @$level - 1;
		$params->{'removeoncancel'} = 1;
		$changed = 1;
	}

	if ($params->{'newlevel'}) {

		push @$level, {
			'text'   => string('PLUGIN_FAVORITES_NAME'),
			'outline'=> [],
		};

		$edit = scalar @$level - 1;
		$params->{'removeoncancel'} = 1;
		$changed = 1;
	}

	# save session data for next call
	$sessions{ $sessId } = {
		'opml'     => $opml,
		'deleted'  => $deleted,
		'autosave' => $autosave,
	};

	# save each change if autosave set
	if ($changed && $opml && $autosave) {
		$opml->save;
	}

	# set params for page build
	$params->{'sess'}      = $sessId;
	$params->{'favorites'} = !$favs;
	$params->{'title'}     = $opml->title;
	$params->{'filename'}  = $opml->filename;
	$params->{'deleted'}   = defined $deleted ? $deleted->{'text'} : undef;
	$params->{'editmode'}  = defined $edit;
	$params->{'autosave'}  = $autosave;

	if ($opml && $opml->error) {
		$params->{'errormsg'} = string('PLUGIN_FAVORITES_' . $opml->error) . " " . $opml->filename;
		$opml->clearerror;
		($level,$indexLevel)=($opml->toplevel,0);
	}

	# add the entries for current level
	my @entries;
	my $i = 0;

	foreach my $opmlEntry (@$level) {
		my $entry = {
			'title'   => $opmlEntry->{'text'} || '',
			'url'     => $opmlEntry->{'URL'} || $opmlEntry->{'url'} || '',
			'audio'   => (defined $opmlEntry->{'type'} && $opmlEntry->{'type'} =~ /audio|playlist/) ? 1 : 0,
			'outline' => $opmlEntry->{'outline'},
			'edit'    => (defined $edit && $edit == $i) ? 1 : 0,
			'index'   => join('.', (@indexPrefix, $i++)),
			'icon'    => $opmlEntry->{'icon'},
		};

		if ($favs && $entry->{'url'}) {
			$entry->{'favorites'} = $favs->hasUrl($entry->{'url'}) ? 2 : 1;
		}

		push @entries, $entry;
	}

	$params->{'entries'}       = \@entries;
	$params->{'levelindex'}    = join '.', @indexPrefix;
	$params->{'indexOnLevel'}  = $indexLevel;

	# add the top level title to pwd_list
	push @{$params->{'pwd_list'}}, {
		'title' => $opml && $opml->title || string('PLUGIN_FAVORITES_EDITOR'),
		'href'  => 'href="' . ($params->{webroot} || '/') . 'plugins/radiostationsfavorites/index.html?radioView=browse"',
	};

	# add remaining levels up to current level to pwd_list
	for (my $i = 0; $i <= $#indexPrefix; ++$i) {

		my @ind = @indexPrefix[0..$i];
		push @{$params->{'pwd_list'}}, {
			'title' => $opml->entry(\@ind)->{'text'},
			'href'  => 'href="index.html?index=' . (join '.', @ind) . '&sess=' . $sessId . '"',
		};
	}

	# fill template and send back response
	my $callback = shift;
	$params->{pageHeaderInfo}='<a id="rs-native-back" href="'.($params->{webroot} || '/').'plugins/radiostationsfavorites/index.html?radioView=browse&amp;player='.uri_escape_utf8($params->{player} || '').'" target="_self">&#8592; '.cstring($client,'PLUGIN_RADIOSTATIONS_BACK').'</a> &nbsp; | &nbsp; <a href="'.($params->{webroot} || '/').'plugins/RadioStations/settings/basic.html" target="_blank">'.cstring($client,'PLUGIN_RADIOSTATIONS_EDITOR_IMPORT').'</a>';
	my $output = Slim::Web::HTTP::filltemplatefile('plugins/Favorites/index.html', $params);
    # Render the actual installed LMS template, redirecting only editor endpoints.
    $$output =~ s{plugins/Favorites/index\.html}{plugins/RadioStations/editor/index.html}g;
    $$output =~ s{plugins/Favorites/html/(favorites|Favorites)\.js}{plugins/RadioStations/editor/html/$1.js}g;
    # Radio favorites are a flat list; file import/export and folders are not exposed.
    $$output =~ s{<input\b[^>]*(?:newlevel|name="import"|value="[^"<>]*"[^>]*onclick="[^"]*'import&)[^>]*>}{}gi;

	$callback->($client, $params, $output, @_);
}

sub asyncCBContent {
	# callback for async http content fetching
	# causes indexHandler to be processed again with stored params + fetched content
	my $http = shift;
	my ($client, $params, $callback, $httpClient, $response) = @{ $http->params('args') };

	$params->{'fetched'}        = 1;
	$params->{'fetchedcontent'} = $http->content;

	indexHandler($client, $params, $callback, $httpClient, $response);
}

sub asyncCBContentType {
	# callback for establishing content type
	# causes indexHandler to be processed again with stored params + fetched content type
	my ($http, $client, $params, $callback, $httpClient, $response) = @_;

	$params->{'fetched'} = 1;
	$params->{'fetchedtype'} = $http->response->content_type;

	$http->disconnect;

	indexHandler($client, $params, $callback, $httpClient, $response);
}

sub asyncCBContentTypeError {
	# error callback for establishing content type - causes indexHandler to be processed again with stored params
	my ($http, $error, $client, $params, $callback, $httpClient, $response) = @_;

	$params->{'fetched'} = 1;

	indexHandler($client, $params, $callback, $httpClient, $response);
}


1;

