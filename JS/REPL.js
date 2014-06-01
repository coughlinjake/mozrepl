/*
 * REPL.js - REPL API.
 */

/*jshint sub:true */
/*jshint quotmark:true */

var registers = {
    "LOG": ""
};
var nextRegister = 1;

function repl_version() {
/*jshint strict:false */
    this.print("MozREPL Version 1.1.0");
}

/*
 * ================================================================================
 * == Registers
 * ================================================================================
 */

/*
 * clear_all_regs()
 */
function clear_all_regs() {
/*jshint strict:false */
    registers = {
        "LOG" : ""
    };
    nextRegister = 1;
}

/*
 * reg(obj)
 */
function reg(obj) {
/*jshint strict:false */
    if (!obj) { return undefined; }
    registers[nextRegister] = obj;
    return nextRegister++;
}

/*
 * reg_as(regid, obj)
 */
function reg_as(regid, obj) {
/*jshint strict:false */
    registers[regid] = obj;
    return obj;
}

/*
 * deref(regid)
 *   If regid is a number, returns the value in the register whose
 *   id is regid.  Otherwise, assumes an object was passed in and
 *   simply returns the object.
 */
function deref(regid) {
/*jshint strict:false */
    if (regid instanceof Number  || typeof regid === "number") {
        return registers[regid];
    }
    return regid;
}

/*
 * clear_regids(regid, regid, ...)
 */
function clear_regids() {
/*jshint strict:false */
    var l = arguments.length;
    var i;
    for (i = 0; i < l; i++) {
        delete registers[arguments[i]];
    }
}

/*
 * ================================================================================
 * == window, browser, document, content
 * ================================================================================
 */

function get_window()       { return registers['window']; }
function get_browser()      { return registers['browser']; }
function get_content()      { return registers['content']; }
function get_document()     { return registers['content'].document; }
function get_log()          { return registers.LOG; }

/*
 * ================================================================================
 * == Logging
 * ================================================================================
 */

function Log() {
    // if Array Generics are available:
    var args = Array.slice(arguments);
    // otherwise:
    // var args = Array.prototype.slice.call(arguments);
    registers.LOG += args.join('') + "\n";
}

function LogClear() {
    registers.LOG = "";
}

function GetLog() {
    this.rc_ok( registers.LOG );
    this.LogClear();
}

/*
 * function Log()      { }
 * function LogClear() { }
 * function GetLog()   { this.rc_ok( "==LOGGING is currently DISABLED=="); }
 */


/*
 * ================================================================================
 * == Values
 * ================================================================================
 */

function as_array(obj) {
/*jshint strict:false */
    if (obj instanceof Array) {
        return obj;
    }
    return [ obj ];
}

function print_json(json) {
/*jshint strict:false */
    this.print("\n==BEGIN-JSON==");
    this.print(json);
    this.print("\n==END-JSON==\n");
}

/*
 * rc_ok(jsvar)
 *
 * jsvar is the SUCCESSFUL result of executing REPL API calls.
 * Convert jsvar to a JSON string and "return" it to the REPL client.
 * In this case, no "register" variables are created in order to
 * proxy jsvar.  Instead, jsvar is sent back to the client "as is".
 *
 * Therefore, jsvar must be completely represented by
 * primitive types (String, Number, Boolean) that can also be
 * represented at the client.
 */
function rc_ok(jsvar) {
/*jshint strict:false */
    this.print_json
        (
            JSON.stringify({
                "status": "OK",
                "result": jsvar
            })
        );
}

/*
 * rc_fail(exp, msg)
 *
 * The execution of REPL API calls has failed, possibly with an exception.
 * Return this failure to the REPL client.
 *
 * ALL failures provide ONLY a string message to be returned to the
 * client.  NO register variables are EVER created for failures,
 * eliminating any need for a "wrapped" version.
 */
function rc_fail(exp, msg) {
/*jshint strict:false */
    this.print_json
        (
            JSON.stringify({
                "status": "ERROR",
                "exception": exp,
                "result": msg
            })
        );
}

/*
 * ================================================================================
 * == Apply
 * ================================================================================
 */

/*
 * apply(list, func) - Call func on every item in list and collect the results in a new list.
 *   func MUST use return with a value and has the form:
 *      function (item) { ...; return rc; }
 */
function apply(list, func) {
    return list.map( func );
}

/*
 * ================================================================================
 * == Waiting
 * ================================================================================
 */

/* retry_until(params)
 *     Wait until cond() returns true, performing max_attempts before failing.
 *     On success, if on_succ is defined, call on_succ().
 *     On failure, if on_fail is defined, call on_fail().
 */
function retry_until(params) {
/*jshint strict:false */
/*jshint sub:true */
/*jshint quotmark:true */

    var repl    = this;
    var win     = this.get_window();

    var max_attempts = params['max_attempts'] || 100;

    var sleep        = params['sleep'] || 500;
    if (sleep < 30) {
        // caller most likely provided unit of seconds, but
        // setTimeout() uses unit of milliseconds.
        sleep = sleep * 1000;
    }

    var cond = params['cond'];

    var on_succ = params['on_succ'];
    if (!on_succ) {
        on_succ = function(rc) { repl.rc_ok(rc); };
    }
    else if (on_succ instanceof String || typeof on_succ === "string") {
        if (on_succ === 'nothing') {
            on_succ = function(rc) { };
        } else {
            throw new Error('invalid on_succ ('+on_succ+')');
        }
    }

    // if on_fail has any value at all, use it.
    // otherwise, when on_fail is null or missing, use do_fail().
    var on_fail = params['on_fail'];
    if (!on_fail) {
        on_fail = function(rc) { repl.rc_fail(null, rc); };
    }
    if (on_fail instanceof String || typeof on_fail === "string") {
        if (on_fail === 'nothing') {
            on_fail = function(rc) { };
        } else {
            throw new Error('invalid on_fail ('+on_fail+')');
        }
    }

    function _retry(attempts) {
        if (attempts <= 0) {
            on_fail('TIMEOUT EXPIRED BEFORE SUCCESS');
        } else {
            var rc = cond();
            if (rc) {
                on_succ(rc);
            } else {
                win.setTimeout( function () { _retry(attempts - 1); }, sleep, false );
            }
        }
    }

    _retry(max_attempts);
}

/*
 * ================================================================================
 * ==  Find elements
 * ================================================================================
 */

function _node_func(node) { return node; }

/*
 * xpath_first(xpath, context, nodefunc) - Find the first result of the XPath expression and pass it
 * it to nodefunc and return the result.
 *
 * If context is null, document is used.
 * If nodefunc is null, the node itself is returned.
 *
 */
function xpath_all(xpath, context, nodefunc) {
/*jshint strict:false */
    var doc = this.get_document();
    if (!context)  { context = doc; }
    if (!nodefunc) { nodefunc = _node_func; }

    var result = doc.evaluate(xpath, context, null, Components.interfaces.nsIDOMXPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);

    if (result.snapshotLength === 0) {
        return null;
    }

    var a = [];
    var i;
    for (i = 0; i < result.snapshotLength; i++) {
        a[i] = nodefunc(result.snapshotItem(i));
    }

    return a;
}

/* doc_xpath(xpath, root, nodefunc) - Evaluate an XPath expression against a specific document object.
 */
function doc_xpath(xpath, root, nodefunc) {
/*jshint strict:false */
    if (!root)     { root = this.get_document(); }
    if (!nodefunc) { nodefunc = _node_func; }

    var doc = root.nodeType === 9 ? root : root.ownerDocument;

    var result = doc.evaluate(xpath, root, null, Components.interfaces.nsIDOMXPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);

    if (result.snapshotLength === 0) {
        return null;
    }

    var a = [];
    var i;
    for (i = 0; i < result.snapshotLength; i++) {
        a[i] = nodefunc(result.snapshotItem(i));
    }

    return a;
}

/* doc_xpath_attr(xpath, attr, root) - Get the value of a specific attribute.
 *
 */
function doc_xpath_attr(xpath, attr, root) {
/*jshint strict:false */
    return doc_xpath(xpath, root, function(node) { return node.getAttribute(attr); });
}

function doc_xpath_html(xpath, root) {
/*jshint strict:false */
    return doc_xpath(xpath, root, function(node) { return node.outerHTML; });
}

function doc_xpath_text(xpath, root) {
/*jshint strict:false */
    return doc_xpath(xpath, root, function(node) { return node.textContent; });
}

function doc_inflate(xpath, root, fields) {
/*jshint strict:false */
    var repl = this;
    return repl.doc_xpath(xpath, root, function(node) { return repl.inflate_obj(node, fields); });
}

/*
 * xpath_first(xpath, context, nodefunc) - Find the first result of the XPath expression and pass it
 * it to nodefunc and return the result.
 *
 * If context is null, document is used.
 * If nodefunc is null, the node itself is returned.
 *
 */
function xpath_first(xpath, context, nodefunc) {
/*jshint strict:false */
    var doc = this.get_document();
    if (!context)  { context = doc; }
    if (!nodefunc) { nodefunc = _node_func; }

    var result = doc.evaluate(xpath, context, null, Components.interfaces.nsIDOMXPathResult.FIRST_ORDERED_NODE_TYPE, null);
    result = result.singleNodeValue;
    if (!result) {
        return null;
    }
    return nodefunc(result);
}

/*
 * xpath_all_attr(xpath, attr, context)
 * xpath_attr(xpath, attr, context)
 */
function xpath_all_attr(xpath, attr, context) {
/*jshint strict:false */
    return xpath_all(xpath, context, function(node) { return node.getAttribute(attr); });
}
function xpath_attr(xpath, attr, context) {
/*jshint strict:false */
    return xpath_first(xpath, context, function(node) { return node.getAttribute(attr); });
}


/*
 * xpath_all_text(xpath, context)
 * xpath_text(xpath, context)
 */
function xpath_all_text(xpath, context) {
/*jshint strict:false */
    return xpath_all(xpath, context, function(node) { return node.textContent; });
}
function xpath_text(xpath, context) {
/*jshint strict:false */
    return xpath_first(xpath, context, function(node) { return node.textContent; });
}

/*
 * inflate_obj(root, objdesc) - Construct a JavaScript object using an object description
 *    which maps object property names to XPath expressions.
 *
 * root can be:
 *   - a String with an XPath expression
 *   - a DOM node
 *
 * objdesc is an array of objects with each object describing one field of the result:
 *   [
 *     {
 *       "prop": "show_name",
 *       "type": "text",
 *       "xpath": ".//a[@class=\"show-name\"]"
 *     },
 *     ...
 *   ]
 *
 */
function inflate_obj(root, fields) {
/*jshint strict:false */
    var repl = this;

    if (!root) { return null; }

    if (root instanceof String || typeof root === "string") {
        root = repl.xpath_first(root, null, null);
        if (!root) { return null; }
    }

    var obj = {};
    var subobj;
    var i;
    for (i = 0; i < fields.length; i++) {
        var field = fields[i];
        var type  = field.type;
        if (type === 'text') {
            obj[field.id] = repl.xpath_text(field.xpath, root);
        }
        else if (type === 'attr') {
            obj[field.id] = repl.xpath_attr(field.xpath, field.attr, root);
        }
        else if (type === 'list') {
            var roots = repl.xpath_all(field.xpath, root, null);
            if (!roots) { continue; }

            var list = [];
            var r;
            for (r = 0; r < roots.length; r++) {
                subobj  = repl.inflate_obj(roots[r], field.obj);
                if (subobj) { list.push(subobj); }
            }

            obj[field.id] = list;
        }
        else if (type === 'obj') {
            subobj  = repl.inflate_obj(field.xpath, field.obj);
            if (field['id']) {
                // property name was provided so sub obj stored as property value
                obj[field.id] = subobj;
            } else {
                // no property name so merge sub obj into obj
                for (var id in subobj) {
                    if (!subobj.hasOwnProperty(id)) { continue; }
                    obj[id] = subobj[id];
                }
            }
        } else {
            throw new Error('xpath "'+field.xpath+'"; invalid type: '+type);
        }
    }

    return obj;
}

function inflate_all(roots, fields) {
/*jshint strict:false */
    var repl = this;

    if (!roots) { return null; }

    if (roots instanceof String || typeof roots === "string") {
        roots = repl.xpath_all(roots, null, null);
        if (!roots) { return null; }
    }

    var objs = [];
    var r;
    for (r = 0; r < roots.length; r++) {
        var obj = repl.inflate_obj(roots[r], fields);
        if (obj) { objs.push(obj); }
    }

    return objs;
}

/*
 * ================================================================================
 * == Wait for elements
 * ================================================================================
 */

/*
 * wait_for_elements(params)
 *
 * A "synchronous" interface to an event-based implementation which will make
 * a reasonable number of attempts evaluating an XPath for results.  When the
 * XPath yields results, those results are passed to on_succ.  If there are no
 * results after a reasonable number of attempts, on_fail is invoked.
 *
 * NOTE: wait_for_elements() is called upon a valid REPL "this" object, but
 * the callback _wait_for_elements() is called with a DIFFERENT "this" object.
 * This requires _wait_for_elements() to close over the original "this" and
 * the original "window" objs.
 */
function wait_for_elements(params) {
/*jshint strict:false */
    var repl = this;
    // repl.Log("WAIT_FOR_ELEMENTS()");
    if (!params['cond']) {
        // repl.Log("\tgenerating COND function");
        var xpath = params['xpath'];
        params['cond'] =
            function () {
                // repl.Log("\tCOND function evaluating xpath |", xpath, "|");
                var elm_array = repl.xpath_all(xpath, null, null);
                // repl.Log("\t\tfound ", (elm_array) ? elm_array.length : 0, " elements!");
                return (elm_array) ? elm_array : null;
            };
    }
    repl.retry_until(params);
}

function wait_for_first_element(params) {
/*jshint strict:false */
    var repl = this;
    var xpath = params['xpath'];
    params['cond'] =
        function () {
            var elm = repl.xpath_first(xpath, null, null);
            return (elm) ? elm : null;
        };
    repl.retry_until(params);
}

/*
 * ================================================================================
 * == Page Navigation
 * ================================================================================
 */

/*
 * get_referrer()
 */
function get_referrer(doc) {
/*jshint strict:false */
    if (!doc) { doc = this.get_document(); }
    return doc.referrer;
}

function get_url(doc) {
/*jshint strict:false */
    if (!doc) { doc = this.get_document(); }
    return doc.location.href;
}

/*
 * goto_url(url, on_ready) - Navigate the browser to the URL +url+.
 *
 * Navigation is a VERY complicated process and this is a VERY simple implementation.
 *
 * The ONLY scenario +goto_url+ ACTUALLY detects is when Firefox fires the +load+
 * event on the document whose URL matches +url+.  When that event and condition
 * BOTH occur, the REPL sends the string +==PAGE IS LOADED==+ to the client.
 *
 */
function goto_url(params) {
/*jshint strict:false */
    var repl     = this;
    var _browser = this.get_browser();
    var _content = this.get_content();

    var url = params['url'];

    var on_succ = params['on_succ'];
    if (!on_succ) {
        on_succ = function(rc) { repl.rc_ok(rc); };
    }

    var on_page_load = function(aEvent) {
        var doc = aEvent.originalTarget;
        if (doc.location.href === _content.location.href) {
            _browser.removeEventListener("load", on_page_load, true);
            on_succ(doc.location.href);
        }
    };

    _browser.addEventListener("load", on_page_load, true);
    _content.location.href = url;
}

/*
 * ================================================================================
 * == Content
 * ================================================================================
 */

/*
 * get_html(elm) - Retrieve the HTML for elm.
 *
 * elm is either:
 *    - a DOM element node
 *    - an array of DOM element nodes
 *    - an XPath which yields DOM element nodes
 */
function get_html(elm) {
/*jshint strict:false */
    if (elm instanceof String || typeof elm === "string") {
        elm = this.xpath_all(elm, null, function(node) { return node; });
    }
    if (elm) {
        return as_array(elm).map( function(node) { return node.outerHTML; } );
    }
    return null;
}

/*
 * get_text(elm) - Retrieve the text content for elm.
 *
 * elm is either:
 *    - a DOM element node
 *    - an array of DOM element nodes
 *    - an XPath which yields DOM element nodes
 */
function get_text(elm) {
/*jshint strict:false */
    if (elm instanceof String || typeof elm === "string") {
        elm = this.xpath_all(elm, null, function(node) { return node; });
    }
    if (elm) {
        return as_array(elm).map( function(node) { return node.textContent; } );
    }
    return null;
}

/*
 * get_attrs(elm) - Retrieve the HTML attributes for elm.
 *
 * elm is either:
 *    - a DOM element node
 *    - an array of DOM element nodes
 *    - an XPath which yields DOM element nodes
 */
function get_attrs(elm) {
/*jshint strict:false */
    if (elm instanceof String || typeof elm === "string") {
        elm = this.xpath_all(elm, null, function(node) { return node; });
    }
    if (elm) {
        return as_array(elm).map(
            function(node) {
                var attrobj = {};
                var nodes=[], values=[];
                var i;
                for (i=0, attrs=node.attributes, l=attrs.length; i<l; i++){
                    var attr = attrs.item(i);
                    attrobj[attr.nodeName] = attr.nodeValue;
                }
                return attrobj;
            } );
    }
    return null;
}

/*
 * set_form_value(elm, value) - Sets a form element's value to the provided value.
 *
 * elm is either a DOM node of a form element or an XPath whose first result
 * yields a DOM node of a form element.
 */
function set_form_value(elm, value) {
/*jshint strict:false */
    if (elm instanceof String || typeof elm === "string") {
        elm = this.xpath_first(elm, null, null);
    }
    if (elm) {
        if (elm.tagName === "SELECT") {
            // find the option whose value matches the value we want
            // and update the SELECT element's selectedIndex.
            for (var opt = 0; opt < elm.options.length; opt++) {
                if (elm.options[opt].value === value) {
                    elm.selectedIndex = opt;
                    return true;
                }
            }
        }
        else if (elm.tagName === "INPUT") {
            elm.value = value;
            return true;
        }
    }
    return false;
}

/*
 * get_form_value(elm) - Get a form element's value.
 *
 * elm is either a DOM node of a form element or an XPath whose first result
 * yields a DOM node of a form element.
 */
function get_form_value(elm) {
/*jshint strict:false */
    if (elm instanceof String || typeof elm === "string") {
        elm = this.xpath_first(elm, null, null);
    }
    if (!elm) {
        return null;
    }
    if (elm.tagName === "SELECT") {
        var opt = elm.selectedIndex;
        return elm.options[opt].value;
    }
    if (elm.tagName === "INPUT") {
        return elm.value;
    }
    return null;
}

/*
 * ================================================================================
 * == Cookies
 * ================================================================================
 */

/*
 * get_doc_cookies(doc) - Retrieve the cookies for the specified Document object.
 *
 * An object is constructed from the cookies and returned.
 *
 */
function get_doc_cookies(doc) {
/*jshint strict:false */
    if (!doc) { doc = this.get_document(); }

    var cookies = {};

    var all = doc.cookie;
    if (all === "") {
        return cookies;
    }

    var list = all.split("; ");
    var i;
    for(i = 0; i < list.length; i++) {
        var cookie = list[i];

        var p = cookie.indexOf("=");

        var name  = cookie.substring(0,p);

        var value = cookie.substring(p+1);
        value = decodeURIComponent(value);

        cookies[name] = value;
    }
    return cookies;
}

/* get_all_cookies(params)
 */
function get_all_cookies(params) {
    var host = params['host'];
    if (!host) {
        throw new Error("'host' is a required parameter");
    }
    if (host) {
        host = host.replace(/[-[\]{}()*+?.,\\^$|#\s]/g, "\\$&");
        host = new RegExp(host, "i");
    }

    var cookieMgr = Components.classes["@mozilla.org/cookiemanager;1"]
                  .getService(Components.interfaces.nsICookieManager);

    var cookies = [];
    for (var e = cookieMgr.enumerator; e.hasMoreElements();) {
        var cookie = e.getNext().QueryInterface(Components.interfaces.nsICookie);
        if (cookie.host.match(host) !== null) {
            var cinfo = {
                "expires" : cookie.expires,
                "host": cookie.host,
                "name": cookie.name,
                "path": cookie.path,
                "isDomain": cookie.isDomain,
                "value": cookie.value
            };
            cookies.push( cinfo );
        }
    }

    return cookies;
}

/*
 * ================================================================================
 * == Browser Tabs
 * ================================================================================
 */

/* get_all_tabs_info() - Gather information about all tabs and return an array
 *    with one entry per tab.
 *
 * @note Only information which can be meaningfully returned to the client
 *    is gathered: tabbrowser_index, location and title.
 */
function get_all_tabs_info() {
/*jshint strict:false */
    var _repl = this;

    var tabs = [];
    var wm = Components.classes["@mozilla.org/appshell/window-mediator;1"]
        .getService(Components.interfaces.nsIWindowMediator);

    // each entry of en is a ChromeWindow
    var en = wm.getEnumerator('navigator:browser');
    while (en.hasMoreElements()) {
        var chromewindow = en.getNext();
        var tabbrowser = chromewindow.gBrowser;

        var numTabs = tabbrowser.browsers.length;
        var i;
        for (i = 0; i < numTabs; i++) {
            var tab = tabbrowser.tabContainer.childNodes[i];
            var doc = tab.linkedBrowser.contentWindow.document;
            tabs.push({
                "tabbrowser_index": i,
                "location": doc.location.href,
                "title": doc.title
            });
        }
    }

    return tabs;
}

/*
 * tab_info(tab) - Return information about the provided tab.  The information returned
 *    is restricted to information which can be conveyed to the REPL client meaningfully.
 *
 *    Currently the following information is returned: location, title.
 *
 */
function tab_info(tabobj) {
/*jshint strict:false */
    if (!tabobj) { return null; }
    var tabinfo = {
        "location": tabobj.doc.location.href,
        "title": tabobj.doc.title
    };
    return tabinfo;
}

/*
 * tab_document(tabobj) - Return the Document object of the provided tab.
 */
function tab_document(tabobj) {
/*jshint strict:false */
    if (!tabobj) { return null; }
    return tabobj.doc;
}

/*
 * selected_tab() - Return the tab object of the currently selected tab.
 *
 */
function selected_tab() {
/*jshint strict:false */
    var tabobj = {
        'tabbrowser': this.get_browser(),
        'tab': this.get_browser().selectedTab
    };
    return tabobj;
}

function all_tabs() {
    var repl = this;

    var tabs = [];

    var wm = Components.classes["@mozilla.org/appshell/window-mediator;1"]
        .getService(Components.interfaces.nsIWindowMediator);

    // each entry of en is a ChromeWindow
    var en = wm.getEnumerator('navigator:browser');
    while (en.hasMoreElements()) {
        var chromewindow = en.getNext();
        var tabbrowser = chromewindow.gBrowser;

        var numTabs = tabbrowser.browsers.length;
        var i;
        for (i = 0; i < numTabs; i++) {
            var tab = tabbrowser.tabContainer.childNodes[i];
            var doc = tab.linkedBrowser.contentWindow.document;
            tabs.push({
                'tabbrowser': repl.get_browser(),
                'tab': tab,
                'doc': doc,
                'location': doc.location.href,
                'title': doc.title
            });
        }
    }

    return tabs;
}

/*
 * tab_new() - Add a new tab.
 */
function tab_new(params) {
/*jshint strict:false */
    var repl = this;
    var browser = this.get_browser();

    var on_succ = params['on_succ'];
    if (!on_succ) {
        on_succ = function(rc) { repl.rc_ok(rc); };
    }

    var url = params['url'] || 'about:blank';
    var tab = browser.addTab(url);
    var newTabBrowser = browser.getBrowserForTab(tab);

    var on_page_load = function () {
        // newTabBrowser.contentDocument.body.innerHTML = "<div>Hello, new tab!</div>";
        newTabBrowser.contentDocument.location.href = url;
        newTabBrowser.removeEventListener("load", on_page_load, true);
        browser.tabContainer.selectedItem = tab;
        on_succ(newTabBrowser.contentDocument.location.href);
    };

    newTabBrowser.addEventListener("load", on_page_load, true);
}

/*
 * tab_activate(tabobj) - Activate the provided tab.
 */
function tab_activate(tabobj) {
/*jshint strict:false */
    if (tabobj) {
        this.get_browser().tabContainer.selectedItem = tabobj.tab;
        registers['browser']  = tabobj.tabbrowser;
        registers['document'] = tabobj.document;
        return true;
    } else {
        return null;
    }
}

/*
 * tab_close(tabobj) - Close the provided tab(s).
 */
function tab_close(tabs) {
/*jshint strict:false */
    if (tabs) {

        return as_array(tabs).map( function(tabobj) {
            var tab = tabobj.tab;
            if (!tab.collapsed) {
                tabobj.tabbrowser.removeTab(tab);
                return true;
            } else {
                return false;
            }
        } );

    } else {
        return null;
    }
}

/* tabs_reset(parms) - Close all of the browser's tabs, then open a new, empty tab.
 *    The intent is to get the browser into a fresh, well-defined state before
 *    executing more automation.
 *
 *    Note that tab_new() returns the browser's URL, which will be "about:blank".
 *
 *    Also note that Firefox may not close the last tab so there will be 2 open
 *    tabs when tabs_reset() returns.  Firefox should have activated the new
 *    blank tab, however.
 *
 */
function tabs_reset(parms) {
    var repl = this;
    repl.tab_close( all_tabs() );
    repl.tab_new(parms);
}

/*
 * find_first_tab(tab_index, url_pat) - Return a tabobj for the first tab which satisfies the
 *    provided criteria.  If no tab satisfies the criteria, returns null.
 *
 *    If url_pat has any value, it should be a string containing a pattern.  A Regexp
 *    will be constructed from the string, and the first tab whose doc.location matches
 *    the Regexp satisfies the criteria.
 *
 *    Otherwise, url_pat should be false.  In this case, tab_index is the integer index
 *    of the tab to return.
 */
function find_first_tab(tab_index, url_pat) {
/*jshint strict:false */
    var r = null;
    if (url_pat) {
        r = url_pat.replace(/[-[\]{}()*+?.,\\^$|#\s]/g, "\\$&");
        r = new RegExp(url_pat, "i");
    }

    var tabobj = null;
    var tab;
    var doc;

    var wm = Components.classes["@mozilla.org/appshell/window-mediator;1"]
        .getService(Components.interfaces.nsIWindowMediator);

    var en = wm.getEnumerator('navigator:browser');
    while (en.hasMoreElements()) {

        var tabbrowser = en.getNext().gBrowser;
        var numTabs = tabbrowser.browsers.length;

        if (!url_pat) {
            if (tab_index < numTabs) {
                tab = tabbrowser.tabContainer.childNodes[tab_index];
                tabobj = {
                    'tabbrowser': tabbrowser,
                    'tab': tab,
                    'document': tab.linkedBrowser.contentWindow.document
                };
            }
            return tabobj;
        }

        var i;
        for (i = 0; i < numTabs; i++) {
            tab = tabbrowser.tabContainer.childNodes[i];
            doc = tab.linkedBrowser.contentWindow.document;
            if (doc.location.href.match(r) !== null) {
                tabobj = {
                    'tabbrowser': tabbrowser,
                    'tab': tab,
                    'document': doc
                };
                return tabobj;
            }
        }
    }

    return null;
}

/*
 * ================================================================================
 * == Frames
 * ================================================================================
 */

/* get_frames_info()
 */
function get_frames_info() {
    var repl = this;
    return repl._frame_info( repl.get_window() );
}

function _frame_info(frame) {
    var repl = this;
    var info = {};
    try {
        info['url']   = frame.window.location.href;
        info['name']  = frame.name;

        // create 'frames' array in info object then set local
        // variable frames_info to refer to it.
        info['frames'] = [];
        var frames_info = info['frames'];

        var frames = frame.frames;
        var i, f;
        info['num_frames'] = frames.length;
        for (i = 0; i < frames.length; ++i) {
            fi = repl._frame_info(frames[i]);
            fi['index'] = i;
            frames_info.push(fi);
        }
    } catch(e) {
        info['name'] = '<#EXCEPTION>';
    }
    return info;
}

/* frame_find(matchfunc) - Find a particular frame's window object by iterating over all
 *    the frames and passing each to matchfunc.
 *
 *    frame_find().location.href == URL in that frame
 *    frame_find().content.document
 */
function frame_find(params) {
/*jshint strict:false */
    var repl = this;

    var frame_url     = params['frame_url'];

    var frame_matcher = params['frame_matcher'];
    if (frame_matcher) {
        // the frame match function was provided without a frame_url
        if (!frame_url) {
            frame_url = 'not provided';
        }
    } else {
        // hopefully a frame_url was provided; use the default match function.
        if (!frame_url) {
            throw new Error("either frame_matcher or frame_url must be provided");
        }

        //repl.Log("FRAME_FIND(",frame_url,")");

        var framere = frame_url.replace(/[-[\]{}()*+?.,\\^$|#\s]/g, "\\$&");
        framere = new RegExp(framere, "i");

        frame_matcher = function(fwin) {
            var href = fwin.window.location.href;
            return href.match(framere) !== null;
        };
    }

    var rc = repl._find_frame(repl.get_window(), frame_matcher);
    if (rc) {
        // repl.Log("\tFOUND the frame (URL: ", rc.window.location.href, ")");
        return rc;
    }

    // repl.Log("\tframe NOT found");
    throw new Error("failed to locate frame with URL '"+frame_url+"'");
}

function _find_frame(frame, frame_matcher) {
    var repl = this;

    if ( frame_matcher(frame) ) {
        return frame;
    }

    var i, rc;
    var frames = frame.frames;
    for (i = 0; i < frames.length; i++) {
        rc = repl._find_frame(frames[i], frame_matcher);
        if (rc) { return rc; }
    }

    return null;
}

// function _walk_frames(frame, frame_func) {
//     var repl = this;

//     frame_func(frame);

//     var i, rc;
//     var frames = frame.frames;
//     for (i = 0; i < frames.length; i++) {
//         repl._walk_frames(frames[i], frame_func);
//     }

//     return null;
// }

/* frame_wait_for_elements(params)
 */
function frame_wait_for_elements(params) {
    var repl = this;

    // repl.Log("FRAME_WAIT_FOR_ELEMENTS()");
    var frame = repl.frame_find(params);

    var frame_doc = frame.window.document;
    var xpath = params['xpath'];

    params['cond'] =
        function() {
            // repl.Log("\tcalling repl.doc_xpath(",xpath,")");
            var elm_array = repl.doc_xpath(xpath, frame_doc, null);
            // repl.Log("\t\t", (elm_array) ? "RESULTS" : "nada");
            return (elm_array) ? elm_array : null;
        };

    repl.wait_for_elements(params);
}

/* frame_wait_for_first_element(params)
 */
function frame_wait_for_first_element(params) {
    var repl = this;

    // repl.Log("FRAME_WAIT_FOR_FIRST_ELEMENT()");
    var frame = repl.frame_find(params);

    var frame_doc = frame.window.document;
    var xpath = params['xpath'];

    params['cond'] =
        function() {
            var elm = repl.doc_xpath(xpath, frame_doc, null);
            if (elm instanceof Array || typeof elm === "array") {
                if (elm.length >= 1) {
                    elm = elm[0];
                } else {
                    elm = null;
                }
            }
            return elm ? elm : null;
        };

    repl.wait_for_elements(params);
}

/* frame_check_for_html(parms) - Locate the frame by its URL, then immediately evaluate an XPath on that
 *    frame's document.
 *
 * If the XPath succeeds, retrieve the HTML and call it a success.
 *
 * Otherwise, fail immediately.
 */
function frame_check_for_html(params) {
    var repl = this;
    var frame = repl.frame_find(params);
    var frame_doc = frame.window.document;
    var elms = repl.doc_xpath(params['xpath'], frame_doc, null);
    if (elms) {
        return repl.get_html(elms);
    } else {
        return null;
    }

}

function frame_document(params) {
    var repl = this;
    var frame  = repl.frame_find(params);
    //repl.Log("frame_document() : returning doc '"+frame.window.document.location.href+"'");
    return frame.window.document;
}

/*
 * ================================================================================
 * == Events
 * ================================================================================
 */

/*
 * _click_event(target) - Private API function to perform a click on a DOM node.
 */
function _click_event(target) {
/*jshint strict:false */
    if (target.click) {
        target.click();
    } else {
        var event = target.ownerDocument.createEvent('MouseEvents');
        event.initMouseEvent('click', true, true, target.ownerDocument.defaultView,
            0, 0, 0, 0, 0, false, false, false,
            false, 0, null);
        target.dispatchEvent(event);
    }
    return 'CLICKED';
}

/*
 * do_click(obj) - Click on the provided object.
 */
function do_click(obj) {
/*jshint strict:false */
    return this._click_event(obj);
}

/*
 * ================================================================================
 * == Initialize
 * ================================================================================
 */

function repl_initialize(content) {
/*jshint strict:false */
    var _repl = this;
    var _workContext = this._workContext;

    if (!registers['browser']) {
        var wm = Components.classes["@mozilla.org/appshell/window-mediator;1"]
                           .getService(Components.interfaces.nsIWindowMediator);
        var win = wm.getMostRecentWindow('navigator:browser');
        if (win) {
            registers['window']  = win;
            registers['content'] = win.content;
            registers['browser'] = win.gBrowser;
            this.print("==REPL IS INITIALIZED==");
        }
        else if ('window' in _workContext) {
            // there is no window so we need to create one.  however,
            // window.open() returns BEFORE the window is fully initialized.
            // EVERY MOTHER FUCKING ATTEMPT AT REGISTERING THE PROPER
            // MOTHER FUCKING ONLOAD EVENT FAILED!
            //
            // so, get the process of opening a new window started then
            // tell the MOTHER FUCKING client to FUCK OFF!
            //
            // client will have to wait... how long?  HOW THE MOTHER FUCK
            // SHOULD I KNOW?  but try again MOTHER FUCKING LATER!
            _workContext.window.open('about:blank');
            this.print("==REPL IS NOT INITIALIZED==");
        } else {
            throw new Error('No window can be discovered!');
        }
    }
}
