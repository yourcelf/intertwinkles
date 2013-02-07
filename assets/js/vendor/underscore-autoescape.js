// Underscore Template Auto-Escaper
// --------------------------------
//
// Installation
// ------------
//
// 1. Include underscore.js. http://documentcloud.github.com/underscore/
// 2. Include this file after underscore.js.
//
// Usage
// -----
//
// _.template(…) will now automatically escape values when using the
// <%= … %> interpolation. If you wish to use the traditional, non-escaped
// interpolation, use <%- … %>.
//
// Bonus: _.escapeHTML(string) will HTML escape string.
//
// Similar to an implementation by Vladimir Dronnikov. See:
//
//   https://github.com/dvv/underscore/commit/a4f4d30440f52c7cef26e8574e8eae384a66db9f

(function() {

    // YUI3's Y.Escape.html() with String typecasting.
    //
    // Code:    https://github.com/yui/yui3/blob/3.3.0/src/escape/js/escape.js
    // License: http://developer.yahoo.com/yui/license.html
     
    var HTML_CHARS = {
        '&': '&amp;',
        '<': '&lt;',
        '>': '&gt;',
        '"': '&quot;',
        "'": '&#x27;',
        '/': '&#x2F;',
        '`': '&#x60;'
    };
    
    var _htmlReplacer = function (match) {
        return HTML_CHARS[match];
    };

    var escapeHTML = function (string) {
        if (string === null || typeof string === "undefined") {
            string = "";
        } else {
            string = String(string);
        }
        return string.replace(/[&<>"'\/`]/g, _htmlReplacer);
    };
    
    // A patched version of Underscore's template with automatic escaping.
    //
    // Code:    https://github.com/documentcloud/underscore/blob/1.1.6/underscore.js
    // License: https://github.com/documentcloud/underscore/blob/1.1.6/LICENSE
     
    var templateSettings = {
        evaluate    : /<%([\s\S]+?)%>/g,
        interpolate : /<%-([\s\S]+?)%>/g,
        autoEscape  : /<%=([\s\S]+?)%>/g
    };

    var template = function(str, data) {
        var c  = _.templateSettings;
        var tmpl = 'var __p=[],__e=_.escapeHTML,print=function(){__p.push.apply(__p,arguments);};' +
          'with(obj||{}){__p.push(\'' +
          str.replace(/\\/g, '\\\\')
             .replace(/'/g, "\\'")
             .replace(c.autoEscape, function(match, code) {
               return "',__e(" + code.replace(/\\'/g, "'") + "),'";
             })
             .replace(c.interpolate, function(match, code) {
               return "'," + code.replace(/\\'/g, "'") + ",'";
             })
             .replace(c.evaluate || null, function(match, code) {
               return "');" + code.replace(/\\'/g, "'")
                                  .replace(/[\r\n\t]/g, ' ') + "__p.push('";
             })
             .replace(/\r/g, '\\r')
             .replace(/\n/g, '\\n')
             .replace(/\t/g, '\\t')
             + "');}return __p.join('');";
        var func = new Function('obj', tmpl);
        return data ? func(data) : func;
    };
    
    var mixins = {
        escapeHTML:       escapeHTML,
        templateSettings: templateSettings,
        template:         template
    };
    
    if (window._) {
        window._.extend(window._, mixins);
    }

})();
