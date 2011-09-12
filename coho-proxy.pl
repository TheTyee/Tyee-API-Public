#!/usr/bin/env perl

=head1 The Tyee Public API Overview

The Tyee Public API currently enables you to programatically access stories published on L<http://thetyee.ca/> going back to roughly 2003. Each story object includes a number of properties, including: titles, teasers, bylines, and meta data like the article's section or keywords (see the JSON example linked below for a relatively complete reference). As the API improves, it will provide additional meta data, like name entities, e.g.: people, places, and so on.

This is a very early release of this public API. Things might change, so be sure to join the mailing list for updates: link TK. 

Currently, the API is limited to just stories. Eventually, we hope endpoints for C<contributors>, C<commenters>, C<comments>, and C<series>. If you have suggestions, please post a note in the mailing list.

This API is the same API that we use to provide data to The Tyee's HTML5 mobile app (L<http://thetyee.ca/News/2011/04/11/MobileApp/>). As we build out more serices on top of this API, we hope to expand the scope of what it can do.

--The Tyee

=head2 Copyright notice

=item * Stories

Except where otherwise noted, content made available via this API is copyright The Tyee and the attributed authors.

=item * Photographs & illustrations

Except where otherwise noted, images on this site are copyright the attributed photographer/illustrator or representative agency. 

=item * Creative Commons License

This work is licensed under a Creative Commons Attribution-NonCommercial-NoDerivs 3.0 Unported License. You are free to copy, distribute and transmit the work provided you attribute the work, do not use the work for commercial purposes, not alter, transform, or build upon this work.

=item * Common sense note

Obviously, the API is being made public so that people can specifically build, experiement, and innovate upon it (the API). At the same time, we ask that you respect the original form of the content -- the stories, the photos, etc. -- by not altering them from the original.

=head2 Terms of Use

=over

=item * API authentication and rate limiting

At the moment, we are not requiring authentication to the API, nor are we limiting the number of times that you can make a request to the API. The extent to which we do, or do not, implement these rests with those of you who use the API. If resources are used wisely and respectfully, there may not be a need to implement either.

=item * Commerical use

How do we feel about people using the API to create a commercial product, i.e.: an iOS app that they charge for? Not necessarily a bad thing, as long as they don't imply any endorsement by The Tyee.

=item * Be a good Internet citizen

Instead of getting the laywers involved, we would like to simply ask that you be a good Internet citizen: use the API as you would if you were the one providing it. Be respectful and be courteous. Join the mailing list and let us know what you're working on. Give us a heads-up and we'll do the same for API changes, sevice outages, and so on. Most importantly, engage with the spirit of making the Ineternet better for everyone.

=back

=head2 Basic API information

B<URL:> L<http://api.thetyee.ca/v1>

B<Formats:> json, jsonp

B<HTTP Method:> GET

B<Requires Authentication:> Not currently. Might in the future.

B<API rate limit:> No limits currently. Rate limits will apply in future versions.

B<Callback:> Available on all endpoints. If supplied, the response will use the JSONP format with a callback of the given name.

Example JSON representation of a story: https://gist.github.com/965479

=cut

use local::lib '/var/home/tyeeapi/perl5';
use Mojolicious::Lite;
use JSON;
use LWP::UserAgent;
use HTTP::Request::Common;
use Date::Format;

get '/' => sub {
    my $self = shift;
    $self->render_text(
        'Welcome to The Tyee Public API. You probably want to start <a href="/">here</a>.'
    );
};

=head1 Stories, latest, grouped by section

Returns a list of stories, ordered reverse chronologically by cover date, grouped by major site section, e.g.:
Today's Features, News, Opinion, etc.

Returns four stories per group.

B<URL:> L<http://api.thetyee.ca/v1/latest/grouped>

B<Formats:> json, jsonp

B<HTTP Method:> GET

B<Requires Authentication:> Not currently. Might in the future.

B<API rate limit:> No limits currently. Rate limits will apply in future versions.

B<Parameters:> None.

=cut 

get '/latest/grouped' => sub {
    my $m = shift;

    my @time = gmtime( time );
    my $now = strftime( "%Y-%m-%dT%TZ", @time );

    my $fetch_subset = sub {
        my $query = shift;
        my $tag   = shift;

        my $ua = LWP::UserAgent->new;
        my $r  = $ua->post( "http://localhost:9200/tyee/story/_search",
            Content => encode_json( $query ) );
        my $j = decode_json( $r->content );

        foreach my $node ( @{ $j->{'hits'}->{'hits'} } ) {
            $node->{'_source'}->{'group'} = $tag;
        }

        return $j;
    };

    # today's features
    my $elastic = {
        from   => 0,
        size   => 4,
        "sort" => [ { "storyDate" => { "reverse" => 1 } } ],
        query  => {
            field => { section => "Opinion News Mediacheck Arts Books Life" }
        }
    };
    my $structure = &$fetch_subset( $elastic, "Today's Features" );

    # the hook
    $elastic->{'size'} = 8;
    $elastic->{'query'} = { field => { story_type => "blog" } };
    my $j = &$fetch_subset( $elastic, "The Hook Blog" );
    push @{ $structure->{'hits'}->{'hits'} }, @{ $j->{'hits'}->{'hits'} };

    # news sections
    my %titles = ( Arts => "Arts & Culture" );
    $elastic->{'size'} = 6;
    foreach my $section ( qw/News Opinion Mediacheck Arts Books Life/ ) {
        $elastic->{'query'} = { field => { section => $section } };
        $j = &$fetch_subset( $elastic, $titles{$section} || $section );
        push @{ $structure->{'hits'}->{'hits'} }, @{ $j->{'hits'}->{'hits'} };
    }

    # package up and render
    my $json = nice_encode_json( $structure );
    proxy_render( $m, $json );
};

=head1 Stories, latest

Returns stories publish on The Tyee, sorted in reverse chonological order by cover date.

B<URL:> L<http://api.thetyee.ca/v1/latest/>[number]

B<Formats:> json, jsonp

B<HTTP Method:> GET

B<Requires Authentication:> Not currently. Might in the future.

B<API rate limit:> No limits currently. Rate limits will apply in future versions.

B<Parameters:> Number of stories to return (maximum 50). Optional.

=cut 

get '/latest/:count' => [ count => qr/\d+/ ] => { count => 20 } => sub {
    my $m = shift;

    my $count = $m->param( "count" );
    $count = 50 if $count > 50;

    my @time = gmtime( time );
    my $now = strftime( "%Y-%m-%dT%TZ", @time );

    my $ua = LWP::UserAgent->new;
    my $r  = $ua->post( "http://localhost:9200/tyee/story/_search",
              Content => '{ "from": 0, "size": ' 
            . $count
            . ', "sort" : [ { "storyDate" : { "reverse" : true } } ], "query" : { "range" : { "storyDate": { "to" : "'
            . $now
            . '"} } } }' );

    proxy_render( $m, json_to_json( $r->content ) );
};

=head1 Stories, latest, teasers only

Returns a list of the latest stories published on The Tyee, sorted in reverse chonological order by cover date, but only provides the following properties: title, teaser, _type, and _id. 

B<URL:> L<http://api.thetyee.ca/v1/latest/short/>[number]

B<Formats:> json, jsonp

B<HTTP Method:> GET

B<Requires Authentication:> Not currently. Might in the future.

B<API rate limit:> No limits currently. Rate limits will apply in future versions.

B<Parameters:> Number of stories to return (maximum 50). Optional.

=cut 

get '/latest/short/:count' => [ count => qr/\d+/ ] => { count => 20 } => sub {
    my $m = shift;

    my $count = $m->param( "count" );
    $count = 50 if $count > 50;

    my @time = gmtime( time );
    my $now = strftime( "%Y-%m-%dT%TZ", @time );

    my $ua = LWP::UserAgent->new;
    my $r  = $ua->post( "http://localhost:9200/tyee/story/_search",
        Content =>
            '{ "script_fields": {"title": {"script":"_source.title"}, "teaser": {"script":"_source.teaser"}}, "from": 0, "size": '
            . $count
            . ', "sort" : [ { "storyDate" : { "reverse" : true } } ], "query" : { "range" : { "storyDate": { "to" : "'
            . $now
            . '"} } } }' );

    proxy_render( $m, json_to_json( $r->content ) );
};

=head1 Story

Returns a single story object. Example of a response: https://gist.github.com/965479

B<URL:> L<http://api.thetyee.ca/v1/story/>[uuid]

B<Formats:> json, jsonp

B<HTTP Method:> GET

B<Requires Authentication:> Not currently. Might in the future.

B<API rate limit:> No limits currently. Rate limits will apply in future versions.

B<Parameters:> The UUID of the story to return. Required.

=cut 

get '/story/:uuid' => sub {
    my $m = shift;

    my $ua = LWP::UserAgent->new;
    my $r  = $ua->post( "http://localhost:9200/tyee/story/_search",
              Content => '{ "query": {"term": { "_id": "'
            . $m->param( "uuid" )
            . '"} } }' );

    proxy_render( $m, json_to_json( $r->content ) );
};

get '/search/path/(*query)' => sub {
    my $m = shift;

    my $ua      = LWP::UserAgent->new;
    my $elastic = {
        size  => 25,
        query => { field => { path => $m->param( "query" ) } }
    };

    my $r = $ua->post(
        "http://localhost:9200/tyee/story/_search",
        Content => encode_json( $elastic )
    );

    proxy_render( $m, json_to_json( $r->content ) );
};

get '/search/(*query)' => sub {
    my $m = shift;

    my $ua      = LWP::UserAgent->new;
    my $elastic = {
        size  => 25,
        query => { field => { title => $m->param( "query" ) } }
    };

    my $r = $ua->post(
        "http://localhost:9200/tyee/story/_search",
        Content => encode_json( $elastic )
    );

    proxy_render( $m, json_to_json( $r->content ) );
};



=head1 Stories by topic

Returns a list of stories (maximum 25) by section or topic.

B<URL:> L<http://api.thetyee.ca/v1/topic/>[topic]

B<Formats:> json, jsonp

B<HTTP Method:> GET

B<Requires Authentication:> Not currently. Might in the future.

B<API rate limit:> No limits currently. Rate limits will apply in future versions.

B<Parameters:> Topic. Required. (Valid parameters are: News, Opinion, Mediacheck, Arts & Culture, Books, Life, 2010 Olympics, Education, Energy, Environment, Federal Election 2011, Film, Food, Food + Farming, Gender + Sexuality, Health, Housing, Labour, Music, Photo Essays, Podcasts, Politics, Rights + Justice, Science + Tech, Transportation, Travel, Tyee News, Urban Design + Architecture, Video.)

=cut 

get '/topic/:topic' => sub {
    my $m       = shift;
    my $topic   = $m->param( "topic" );
    my $ua      = LWP::UserAgent->new;
    my $elastic = {
        "size" => 25,
        "sort" => [ { "storyDate" => { "reverse" => 1 } } ],
        query => { field => { topics => '"' . $topic . '"' } }
    };

    my $r = $ua->post(
        "http://localhost:9200/tyee/story/_search",
        Content => encode_json( $elastic )
    );

    proxy_render( $m, json_to_json( $r->content ) );
};

=head1 Story by path 

Returns a story by path. 

B<URL:> L<http://api.thetyee.ca/v1/path/>[path]

B<Formats:> json, jsonp

B<HTTP Method:> GET

B<Requires Authentication:> Not currently. Might in the future.

B<API rate limit:> No limits currently. Rate limits will apply in future versions.

B<Parameters:> Path. Required. 

=cut 

get '/path/:path' => sub {
    my $m       = shift;
    my $path   = $m->param( "path" );
    my $ua      = LWP::UserAgent->new;
    my $elastic = {
        query => { field => { path => "' . $path . '" } }
    };

    my $r = $ua->post(
        "http://localhost:9200/tyee/story/_search",
        Content => encode_json( $elastic )
    );

    proxy_render( $m, json_to_json( $r->content ) );
};
app->types->type( js   => 'application/x-javascript; charset=utf-8' );
app->types->type( json => 'application/json; charset=utf-8' );

app->start;

### helper functions ###

# Takes a JSON string and outputs a nicely encoded JSON string
sub json_to_json {
    my $json = shift;

    return nice_encode_json( decode_json( $json ) );
}

# Nicely encodes an object to a JSON string. Unicode characters too!
sub nice_encode_json {
    my $obj = shift;

    return JSON->new->ascii( 1 )->pretty( 1 )->encode( $obj );
}

# Tells Mojo to render some JSON.
# Handles the JSON/JSONP formatting too.
sub proxy_render {
    my $m    = shift;
    my $json = shift;

    $json = $m->param( "callback" ) . "(" . $json . ");"
        if $m->param( "callback" );
    $m->render(
        text   => $json,
        format => ( $m->param( "callback" ) ? "js" : "json" )
    );
}

