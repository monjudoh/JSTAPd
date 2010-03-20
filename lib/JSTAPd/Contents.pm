package JSTAPd::Contents;
use strict;
use warnings;
use FindBin;

sub suite { $_[0]->{suite} }

sub new {
    my($class, $name, $path) = @_;

    my $self = bless {
        name  => $name,
        path  => $path,
        suite => undef,
    }, $class;
    $self->parse if $path =~ /\.t$/;
    $self;
}

sub slurp { $_[0]->{slurp} ||= $_[0]->{path}->slurp }

my $ANON_CLASS_COUNT = 0;

sub parse {
    my $self = shift;

    my $script = $self->slurp;
    my $package = join '::', __PACKAGE__, 'AnonClass', 'Num'.($ANON_CLASS_COUNT++);
    my $code = "
# line 1 $package.pm
package $package; ## 
BEGIN{ \$$package\::IN_THE_PARSE = 1 };
# line 1 $self->{path}
$script;
# line 5 $package.pm
sub path { '$self->{path}' }
sub name { '$self->{name}' }
JSTAPd::Suite::export(__PACKAGE__);
1;";
    do {
        local $FindBin::Bin = $self->{path}->dir;
        eval $code; ## no critic
    };
    $@ and die $@;
    $self->{suite} = $package->new;
}

sub header {
    my($self, %args) = @_;
    my $script = $self->suite->client_script;

    my $html = sprintf <<'HTML', $args{jstapd_prefix}, $args{session}, $args{path}, _default_tap_lib(), $args{include} || 'nop()', $script;
<script type="text/javascript">
(function(){
var jstapd_prefix = '/%s__api/';
var session       = '%s';
var path          = '%s';

%s

// test functions
var tap_count = 0;
var tap_tests = 0;
window.tests = function(num){
    tap_tests = num;
    enqueue(function(){
        get('tests', { num: num });
    });
};
window.ok   = function(val, msg){
    var ret;
    var comment = '';
    try {
        if (val) {
            ret = 'ok';
        } else {
            ret = 'not ok';
        }
    } catch(e) {
        comment = e;
    }

    enqueue(function(){
        tap('ok', {
            ret: ret,
            num: (++tap_count),
            msg: msg,
            comment: comment
        });
    });
};
window.is   = function(got, expected, msg, is_not){
    var ret;
    var comment = '';
    try {
        if (got == expected) {
            ret = is_not ? 'not ok' : 'ok';
        } else {
            ret = is_not ? 'ok' : 'not ok';
        }
    } catch(e) {
        comment = e;
    }

    enqueue(function(){
        tap((is_not ? 'isnt' : 'is'), {
            ret: ret,
            num: (++tap_count),
            msg: msg,
            got: got,
            expected: expected,
            comment: comment
        });
    });
};
window.isnt = function(got, expected, msg){
    is(got, expected, msg, true);
};
window.like = function(got, expected, msg, is_not){
    var ret;
    var comment = '';
    try {
        if (got.search(expected) >= 0) {
            ret = is_not ? 'not ok' : 'ok';
        } else {
            ret = is_not ? 'ok' : 'not ok';
        }
    } catch(e) {
        comment = e;
    }

    enqueue(function(){
        tap((is_not ? 'unlike' : 'like'), {
            ret: ret,
            num: (++tap_count),
            msg: msg,
            got: got,
            expected: expected.toString(),
            comment: comment
        });
    });
};
window.unlike = function(got, expected, msg){
    like(got, expected, msg, true);
};

window.tap_done = function(error){
    enqueue(function(){
        get('tap_done', { error: error }, function(r){
            var div = document.createElement("div");
            div.innerHTML = r.responseText.replace(/\n/g, '<br>');
            tap$tag('body').appendChild(div);
            tap$('jstap_users_body_container').style.display = 'none';
        })
    });
};

window.tap_dump = function(){
    enqueue(function(){
        get('dump', {})
    });
};

window.pop_tap_request = function(cb, opts){
    enqueue(function(){
        get('pop_tap_request', (opts || {}), function(r){
            var json; eval('json = ' + r.responseText);
            cb(json);
        });
    });
};

window.tap_addevent = function(target, event, callback, useCapture){
    if (target.addEventListener) {
        target.addEventListener(event, callback, useCapture);
    } else if(target.attachEvent) {
        target.attachEvent('on'+event, callback);
    }
}

window.tap_xhr = function(){
    return xhr();
};

// for jstapDeferred

// load js libs
jstapDeferred.register('include', function(src){
    var d = new jstapDeferred;
    var script = document.createElement('script');
    var onload = function(){ d.call() };
    if (typeof(script.onreadystatechange) == 'object') {
        script.onreadystatechange = function(){
            if (script.readyState != 'loaded' && script.readyState != 'complete') return;
            onload();
        };
    } else {
        tap_addevent(script, 'load', onload);
    }
    script.src = src;
    tap$tag('body').appendChild(script);
    return d;
});

// waiting testing done
jstapDeferred.register('wait_finish', function(){
    var d = new jstapDeferred;
    if (tap_tests == 0) {
        d.call();
    } else {
        // async done mode
        var do_async = function(){
            if (tap_count >= tap_tests) {
                d.call();
            } else {
                setTimeout(do_async, 10);
            }
        };
        setTimeout(do_async, 10);
    }
    return d;
});

// wait dequeueing
jstapDeferred.wait_dequeue = function(cb){ // cb is for test
    var d = new jstapDeferred;
    var wait = function(){
        if (is_dequeueing()) {
            if (cb && typeof(cb) == 'function') cb(false);
            setTimeout(wait, 100);
        } else {
            if (cb && typeof(cb) == 'function') cb(true);
            d.call();
        }
    };
    setTimeout(wait, 0);
    return d;
};
jstapDeferred.register('wait_dequeue', jstapDeferred.wait_dequeue);

})();
</script>
<script type="text/javascript">
(function(){
window.onload = function(){

jstapDeferred.next(function(){
    // lib load
    return jstapDeferred.next(function(){}).
%s
    ;
}).
next(function(){
   // run test
%s
}).
wait_finish().
next(function(){
    // done
    tap_done('');
});
}

})();

</script>
HTML

}

sub build_html {
    my($self, $head, $body) = @_;
    my $index = $self->slurp;
    $body = sprintf '<div id="jstap_users_body_container">%s</div>', $body;
    $index =~ s/\$HEAD/$head/g;
    $index =~ s/\$BODY/$body/g;
    $index;
}

sub build_index {
    my($class, %args) = @_;
    _default_index(%args);
}

sub _default_index {
    my %args = @_;

    return sprintf <<'HTML', $args{jstapd_prefix}, $args{jstapd_prefix}, ($args{run_once} ? 'true' : 'false'), ($args{auto_open} ? 'true' : 'false'), _default_tap_lib();
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">
<html>
    <head>
        <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
        <meta http-equiv="content-script-type" content="text/javascript">
        <title>JSTAPd main index</title>
<script type="text/javascript">
var jstapd_prefix = '/%s__api/';
var contents_prefix = '/%s/contents/';
var session = '';
var path = '';
var run_once = %s;
var auto_open = %s;

%s

(function(){

var status = {
    tests: []
};
var current_path = '';
function start_next(args){
    var body = tap$tag('body');

    var h = document.createElement("h2");
    var a = document.createElement("a");
    a.href = contents_prefix + args.path;
    a.target = '_blank';
    a.innerHTML = args.path;
    a.name = args.path;
    h.appendChild(a);
    body.appendChild(h);

    var iframe_div = document.createElement("div");
    body.appendChild(iframe_div);

    var iframe = document.createElement("iframe");
    iframe_div.appendChild(iframe);
    iframe.src = contents_prefix + path + '?session=' + session;
    iframe.width = '100%%';

    get('watch_finish', {}, function(r){
        var json; eval('json = ' + r.responseText);
        if (json.status != 0 && json.session == session && json.path == path) {
            finish_and_next(json.tap, json.path, h);
        } else {
            setTimeout(watch, 10);
        }
    });
}

function finish_and_next(json, name, h){
    var msg = ' .. ';
    var is_ok = 0;
    if (json.fail > 0) {
        msg += json.ok + '/' + json.run;
    } else if (json.error) {
        msg += json.ok + '/' + json.run + ' ' + json.error;
    } else {
        msg += 'ok';
        is_ok = 1;
    }
    if (json.tests > 0 && json.tests != json.run) {
        msg += ' # Looks like you planned ' + json.tests + ' test but ran ' + json.run + '.';
        is_ok = 0;
    }

    var span = document.createElement("span");
    span.innerHTML = msg;
    h.appendChild(span);

    status.tests.push({ name: name, msg: msg, is_ok: is_ok });
    get_next();
}

function all_tests_finish(){

    var ul = document.createElement("ul");

    var fails = 0;
    for (i in status.tests) {
        var ret = status.tests[i];
        var li = document.createElement("li");
        var a = document.createElement("a");
        a.href = '#' + ret.name;
        a.innerHTML = ret.name + ret.msg;
        li.appendChild(a);
        ul.appendChild(li);
        if (!ret.is_ok) fails++;
    }
    var results = tap$('results');
    results.appendChild(ul);

    var div1 = document.createElement("div");
    div1.innerHTML = 'Tests=' + status.tests.length + ', Fails=' + fails;
    results.appendChild(div1);
    
    var div2 = document.createElement("div");
    if (fails == 0) {
        div2.innerHTML = 'Result: PASS';
    } else {
        div2.innerHTML = 'Result: FAIL';
    }
    results.appendChild(div2);

    if (run_once) {
        get('exit', {}, function(r){ /* nothing response */ });
        if (auto_open) window.close();
    }
}

function get_next(){
    get('get_next', {}, function(r){
        var json; eval('json = ' + r.responseText);
        if (!json.session) return;
        if (json.path == '-1') {
            all_tests_finish();
            return;
        }
        session = json.session;
        path    = json.path;
        start_next(json);
    });
}


window.onload = function(){
    var button = tap$('make-test');
    if (run_once) {
        button.style.display = 'none';
        get_next();
    } else {
        button.onclick = function(){
            get_next();
        };
    }
};
})();

</script>
    </head>
    <body id="body">
        <div id="results" style="border: 1px solid red; margin: 10px"></div>
        <input type="button" id="make-test" value="make test"/>
    </body>
</html>
HTML
}

sub _default_tap_lib {
    my $js =<<'JS';
// tap lib

// queue
var queue = [];
var is_xhr_running = 0;
var in_dequeueing  = false;
var dequeue = function(){
    if (_is_dequeueing()) return;
    in_dequeueing = true;
    var cb = queue.shift();
    if (cb && typeof cb == 'function') cb();
    in_dequeueing = false;
};
var enqueue = function(cb){
    queue.push(cb);
    dequeue();
};
var _is_dequeueing = function(){ return is_xhr_running || in_dequeueing };
var is_dequeueing  = function(){ return _is_dequeueing() || queue.length };

// ajax base
var xhr = function(){
    return window.ActiveXObject ? new ActiveXObject("Microsoft.XMLHTTP") : new XMLHttpRequest();
};
var get = function(prefix, query, cb){
    var r = xhr();
    var uri = jstapd_prefix + prefix + '?_='+(new Date).getTime();
    query.session = session;
    query.path    = path;
    var query_stack = [uri];
    for (k in query) {
        query_stack.push(encodeURIComponent(k) + '=' + encodeURIComponent(query[k]));
    }

    r.open('GET', query_stack.join('&'));
    r.onreadystatechange = function() {
        if (r.readyState == 4 && r.status == 200) {
            if (cb && typeof cb == 'function') cb(r);
            is_xhr_running--;
            dequeue();
        }
    }
    is_xhr_running++;
    r.send(null);
};
var tap = function(type, query, cb){
    query.type = type;
    get('tap', query, cb);
};

// util
window.tap$ = function(id){
    return document.getElementById(id);
};
window.tap$tag = function(tag){
    return document.getElementsByTagName(tag)[0];
};
JS

    return $js.__jstapdeferred_lib();
}

sub __jstapdeferred_lib {
    return <<'JS';
var id = 1;
window.jstapDeferred = function(){
    this.id = id++;
}

jstapDeferred.prototype = {
    cb: function(v){ return v },
    dnext: null,
    error: null,
    nextval: null,
    retry: function(count, cb){
        if (this.error) return;
        var ret = cb();
    },
    next: function(cb, m){
        this.dnext = new jstapDeferred();
        this.dnext.cb = cb;
        return this.dnext;
    },
    call: function(nextval){
        if (this.error) return;
        var retval;
        try {
            if (this.nextval !== null) nextval = this.nextval;
            retval = this.cb.call(this, nextval);
        } catch (e) {
            this.error = e;
        }
        if (retval instanceof jstapDeferred) {
            retval.dnext = this.dnext;
            if (retval.dnext !== null) retval.dnext.nextval = nextval;
        } else {
            if (this.dnext) this.dnext.call(retval);
        }
    },
    nop: function(r){ return r }
};
jstapDeferred.next = function(f){
    var d = new jstapDeferred;
    if (f) d.cb = f;
    setTimeout(function(){ d.call() }, 0);
    return d;
};

jstapDeferred.wait = function(t){
    var d = new jstapDeferred;
    setTimeout(function(){ d.call() }, t);
    return d;
};

jstapDeferred.retry = function(c,f,o){
    if (!o) o = {};
    var t = o.wait || 0;
    var d = new jstapDeferred;
    var val;
    var retry = function(){
        if (d.dnext.nextval !== null) val = d.dnext.nextval;
        d.dnext.nextval = null;
        var ret = f(c, val);
        if (ret) {
            d.dnext.call(ret);
        } else if (--c <= 0) {
            d.error = 'retry failed';
        } else {
            setTimeout(retry, t);
        }
    };
    setTimeout(retry, 0);
    return d;
};


jstapDeferred.xhr = function(o){
    if (!o) o = {};

    var url = o.url;
    if (!url) throw 'url missing';
    if (o.cache === false) {
        var c = '_='+(new Date).getTime()
        if (url.match(/\?/)) {
            url += '&'+c;
        } else {
            url += '?'+c;
        }
    }

    var r = xhr();
    r.open(o.method, url);
    var d = new jstapDeferred;
    r.onreadystatechange = function() {
        if (r.readyState != 4) return;
        d.call(r);
        return null;
    };
    r.send(null);
    return d;
};

jstapDeferred.pop_request = function(o){
    if (!o) o = {};
    var retry = o.retry;
    var wait  = o.wait || 0;
    var opts  = {};
    if (o.requests) opts.requests = o.requests;

    var d = new jstapDeferred;
    var func = function(req){
        d.dnext.nextval = req; // replace next value
        d.call(req);
        return null;
    };

    if (retry) {
        var f = function(){
            pop_tap_request(function(req){
                if (req.length || --retry <= 0) {
                    return func(req);
                } else {
                    // retry
                    setTimeout(f, wait);
                }
            }, opts);
        };
        setTimeout(f, 0);
    } else {
        pop_tap_request(func, opts);
    }
    return d;
};

jstapDeferred.register = function(n, f){
    this.prototype[n] = function(){
        var a = arguments;
        return this.next(function (v) {
            return f.apply(this, a);
        });
    };
};

jstapDeferred.register('wait', jstapDeferred.wait);
jstapDeferred.register('retry', jstapDeferred.retry);
jstapDeferred.register('xhr', jstapDeferred.xhr);
jstapDeferred.register('pop_request', jstapDeferred.pop_request);

JS
}

1;

__END__

=head1 NAME

JSTAPd::Contents - test file manager

=cut

