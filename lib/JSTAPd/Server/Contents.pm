use strict;
use warnings;
package JSTAPd::Server::Contents;
use HTTP::Engine::Response;
use Data::UUID;

sub handler {
    my($class, $path, $server, $req, $session, $args) = @_;

    my @chain  = split '/', $path;
    my $method = pop @chain;
    my $klass  = join '::', __PACKAGE__, @chain;

    if (@chain && $chain[0] eq 'contents') {
        shift @chain;
        $klass  = 'JSTAPd::Server::Contents::contents';
        $method = join '/', @chain, $method;
    } else {
        no strict 'refs';
        eval 'require $klass' unless %{"$klass\::"};
    }
    unless (!$@ && ($klass->can($method) || $klass->can('AUTOLOAD'))) {
        return HTTP::Engine::Response->new( status => 404, body => 'Not Found' );
    }
    warn "$klass -> $method : " . $req->uri unless $server->run_once;
    $klass->$method($server, $req, $session, $args);
}

# index page
sub index {
    my($class, $server, $req, $session) = @_;
    HTTP::Engine::Response->new( body => JSTAPd::Contents->build_index(
        jstapd_prefix => $server->jstapd_prefix,
        run_once      => $server->run_once,
        auto_open     => $server->auto_open,
    ));
}

package JSTAPd::Server::Contents::contents;
use JSON::XS ();

sub _gen_li {
    my $path = shift;
    sprintf '<li><a href="%s">%s</a></li>', $path, $path;
}
sub _index {
    my($class, $server, $req, $session, $chain) = @_;

    my @li = _gen_li('../');
    $server->contents->each( $chain => sub {
        my($name, $is_dir) = @_;
        return if $name eq 'index';
        push @li, $is_dir ? _gen_li("$name/") : _gen_li($name);
    });

    my $index = $server->contents->fetch_file('index', $chain, 1);
    my $body = sprintf "<ul>\n%s</ul>\n", join("\n", @li);
    HTTP::Engine::Response->new( body => $index->build_html( '', $body ) );
}

sub AUTOLOAD {
    my($class, $server, $req, $session, $args) = @_;
    my $path = our $AUTOLOAD;
    $path =~ s/.+:://;
    my @chain = split '/', $path;
    my $basename = pop @chain;

    if ($basename eq 'index') {
        return _index(@_, \@chain);
    }

    # foo.t
    $server->setup_session_tap($session, $path);

    my $content = $server->contents->fetch_file($basename, \@chain);

    if ($args->{is_api}) {
        return __run_api($content, $server, $req, $session, $args);
    }

    my @include = map {
        ref($_) eq 'SCALAR' ? sprintf "include('/%s/js/%s')", $server->jstapd_prefix, ${ $_ } : "include('$_')"
    } $content->suite->include_ex, $content->suite->include;

    my $index   = $server->contents->fetch_file('index', \@chain, 1);
    return HTTP::Engine::Response->new(
        body => $index->build_html(
            $content->header(
                jstapd_prefix => $server->jstapd_prefix,
                session       => $session,
                path          => $path,
                include       => join('.', @include),
            ),
            $content->suite->html_body,
        ),
    );
}

sub __run_api {
    my($content, $server, $req, $session, $args) = @_;
    my $tap = $server->get_tap($session, $args->{path});

    my $GLOBAL = $tap->global_stash;
    my $METHOD = $req->method;
    my $PATH   = $req->uri->path;

    my $ret;
    my $err;
    do {
        local $@;
        eval {
            $ret = $content->suite->server_api(
                $tap->global_stash,
                $req,
                $req->method,
                $req->uri->path,
            );
        };
        $err = $@;
    };
    if ($err) {
        my $body = sprintf "error: %s\n\t%s\n", $args->{path}, $err;
        warn $body;
        return HTTP::Engine::Response->new( status => 500, body => $body );
    }
    if (ref($ret)) {
        return HTTP::Engine::Response->new( body => JSON::XS->new->ascii->encode($ret) );
    } else {
        return HTTP::Engine::Response->new( body => $ret );
    }
}

package JSTAPd::Server::Contents::js;

sub AUTOLOAD {
    my($class, $server, $req, $session, $args) = @_;
    my $path = our $AUTOLOAD;
    $path =~ s/.+:://;
    $path =~ s/\.js$//;
    $path =~ s/-/_/;

    my $body;
    $body = $class->$path if $class->can($path);
    return HTTP::Engine::Response->new( status => 404, body => 'Not Found' ) unless $body;
    return HTTP::Engine::Response->new( body => $body );
}

sub jquery_jstapd {
    return <<'DONE';
(function ($) {

$.fn.is_visible = function(num){
    window.is($($(this).selector+':visible').length, num, $(this).selector + ' is visible ' + num + ' items');
};

$.fn.isnt_visible = function(){
    var ret = 0;
    if ($($(this).selector+':visible').length == 0) {
        ret = 1;
    }
    window.ok(ret, $(this).selector + ' is not visible');
};

$.fn.is_text = function(val){
    window.is($(this).text(), val, $(this).selector + " text() is '" + val + "'");
};

$.fn.isnt_text = function(val){
    window.isnt($(this).text(), val, $(this).selector + " text() is not '" + val + "'");
};

$.fn.like_text = function(val){
    window.like($(this).text(), val, $(this).selector + " text() like '" + val.toString() + "'");
};

$.fn.unlike_text = function(val){
    window.unlike($(this).text(), val, $(this).selector + " text() unlike '" + val.toString() + "'");
};

$.fn.is_formval = function(val){
    window.is($(this).val(), val, $(this).selector + " form val() is '" + val + "'");
};

$.fn.isnt_formval = function(val){
    window.isnt($(this).val(), val, $(this).selector + " form val() is not '" + val + "'");
};

$.fn.like_formval = function(val){
    window.like($(this).val(), val, $(this).selector + " form val() like '" + val.toString() + "'");
};

$.fn.unlike_formval = function(val){
    window.unlike($(this).val(), val, $(this).selector + " form val() unlike '" + val.toString() + "'");
};

$.fn.is_attr = function(name, val){
    window.is($(this).attr(name), val, $(this).selector + " '" + name + "' attr is '" + val + "'");
};

$.fn.ok_hasClass = function(val){
    window.ok($(this).hasClass(val), $(this).selector + " hasClass '" + val + "'");
};

})(jQuery);
DONE
}

1;

