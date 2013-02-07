(function($){
    /**
     * @page jQuery.toJSON jQuery.toJSON
     * @parent jquerymx.lang
     * 
     *     jQuery.toJSON( json-serializble )
     * 
     * Converts the given argument into a JSON respresentation.
     * 
     * If an object has a "toJSON" function, that will 
     * be used to get the representation.
     * Non-integer/string keys are skipped in the 
     * object, as are keys that point to a function.
     * 
     * json-serializble:
     * The *thing* to be converted.
     */
    $.toJSON = function(o, replacer, space, recurse)
    {
        if (typeof(JSON) == 'object' && JSON.stringify)
            return JSON.stringify(o, replacer, space);

        if (!recurse && $.isFunction(replacer))
            o = replacer("", o);

        if (typeof space == "number")
            space = "          ".substring(0, space);
        space = (typeof space == "string") ? space.substring(0, 10) : "";
        
        var type = typeof(o);
    
        if (o === null)
            return "null";
    
        if (type == "undefined" || type == "function")
            return undefined;
        
        if (type == "number" || type == "boolean")
            return o + "";
    
        if (type == "string")
            return $.quoteString(o);
    
        if (type == 'object')
        {
            if (typeof o.toJSON == "function") 
                return $.toJSON( o.toJSON(), replacer, space, true );
            
            if (o.constructor === Date)
            {
                var month = o.getUTCMonth() + 1;
                if (month < 10) month = '0' + month;

                var day = o.getUTCDate();
                if (day < 10) day = '0' + day;

                var year = o.getUTCFullYear();
                
                var hours = o.getUTCHours();
                if (hours < 10) hours = '0' + hours;
                
                var minutes = o.getUTCMinutes();
                if (minutes < 10) minutes = '0' + minutes;
                
                var seconds = o.getUTCSeconds();
                if (seconds < 10) seconds = '0' + seconds;
                
                var milli = o.getUTCMilliseconds();
                if (milli < 100) milli = '0' + milli;
                if (milli < 10) milli = '0' + milli;

                return '"' + year + '-' + month + '-' + day + 'T' +
                             hours + ':' + minutes + ':' + seconds + 
                             '.' + milli + 'Z"'; 
            }

            var process = ($.isFunction(replacer)) ?
                function (k, v) { return replacer(k, v); } :
                function (k, v) { return v; },
                nl = (space) ? "\n" : "",
                sp = (space) ? " " : "";

            if (o.constructor === Array) 
            {
                var ret = [];
                for (var i = 0; i < o.length; i++)
                    ret.push(( $.toJSON( process(i, o[i]), replacer, space, true ) || "null" ).replace(/^/gm, space));

                return "[" + nl + ret.join("," + nl) + nl + "]";
            }
        
            var pairs = [], proplist;
            if ($.isArray(replacer)) {
                proplist = $.map(replacer, function (v) {
                    return (typeof v == "string" || typeof v == "number") ?
                        v + "" :
                        null;
                });
            }
            for (var k in o) {
                var name, val, type = typeof k;

                if (proplist && $.inArray(k + "", proplist) == -1)
                    continue;

                if (type == "number")
                    name = '"' + k + '"';
                else if (type == "string")
                    name = $.quoteString(k);
                else
                    continue;  //skip non-string or number keys
            
                val = $.toJSON( process(k, o[k]), replacer, space, true );
            
                if (typeof val == "undefined")
                    continue;  //skip pairs where the value is a function.
            
                pairs.push((name + ":" + sp + val).replace(/^/gm, space));
            }

            return "{" + nl + pairs.join("," + nl) + nl + "}";
        }
    };

    /** 
     * @function jQuery.evalJSON
     * Evaluates a given piece of json source.
     **/
    $.evalJSON = function(src)
    {
        if (typeof(JSON) == 'object' && JSON.parse)
            return JSON.parse(src);
        return eval("(" + src + ")");
    };
    
    /** 
     * @function jQuery.secureEvalJSON
     * Evals JSON in a way that is *more* secure.
     **/
    $.secureEvalJSON = function(src)
    {
        if (typeof(JSON) == 'object' && JSON.parse)
            return JSON.parse(src);
        
        var filtered = src;
        filtered = filtered.replace(/\\["\\\/bfnrtu]/g, '@');
        filtered = filtered.replace(/"[^"\\\n\r]*"|true|false|null|-?\d+(?:\.\d*)?(?:[eE][+\-]?\d+)?/g, ']');
        filtered = filtered.replace(/(?:^|:|,)(?:\s*\[)+/g, '');
        
        if (/^[\],:{}\s]*$/.test(filtered))
            return eval("(" + src + ")");
        else
            throw new SyntaxError("Error parsing JSON, source is not valid.");
    };

    /** 
     * @function jQuery.quoteString
     * 
     * Returns a string-repr of a string, escaping quotes intelligently.  
     * Mostly a support function for toJSON.
     * 
     * Examples:
     * 
     *      jQuery.quoteString("apple") //-> "apple"
     * 
     *      jQuery.quoteString('"Where are we going?", she asked.')
     *        // -> "\"Where are we going?\", she asked."
     **/
    $.quoteString = function(string)
    {
        if (string.match(_escapeable))
        {
            return '"' + string.replace(_escapeable, function (a) 
            {
                var c = _meta[a];
                if (typeof c === 'string') return c;
                c = a.charCodeAt();
                return '\\u00' + Math.floor(c / 16).toString(16) + (c % 16).toString(16);
            }) + '"';
        }
        return '"' + string + '"';
    };
    
    var _escapeable = /["\\\x00-\x1f\x7f-\x9f]/g;
    
    var _meta = {
        '\b': '\\b',
        '\t': '\\t',
        '\n': '\\n',
        '\f': '\\f',
        '\r': '\\r',
        '"' : '\\"',
        '\\': '\\\\'
    };
})(jQuery);
(function() {
    /**
     * @function jQuery.cookie
     * @parent jquerypp
     * @plugin jquery/dom/cookie
     * @author Klaus Hartl/klaus.hartl@stilbuero.de
     *
     * `jQuery.cookie(name, [value], [options])` lets you create, read and remove cookies. It is the
     * [jQuery cookie plugin](https://github.com/carhartl/jquery-cookie) written by [Klaus Hartl](stilbuero.de)
     * and dual licensed under the [MIT](http://www.opensource.org/licenses/mit-license.php)
     * and [GPL](http://www.gnu.org/licenses/gpl.html) licenses.
     *
	 * ## Examples
	 * 
	 * Set the value of a cookie.
	 *  
	 *      $.cookie('the_cookie', 'the_value');
	 * 
	 * Create a cookie with all available options.
	 *
     *      $.cookie('the_cookie', 'the_value', {
     *          expires: 7,
     *          path: '/',
     *          domain: 'jquery.com',
     *          secure: true
     *      });
	 *
	 * Create a session cookie.
	 *
     *      $.cookie('the_cookie', 'the_value');
	 *
	 * Delete a cookie by passing null as value. Keep in mind that you have to use the same path and domain
	 * used when the cookie was set.
	 *
     *      $.cookie('the_cookie', null);
	 *
	 * Get the value of a cookie.
     *
	 *      $.cookie('the_cookie');
     *
     * @param {String} [name] The name of the cookie.
     * @param {String} [value] The value of the cookie.
     * @param {Object} [options] An object literal containing key/value pairs to provide optional cookie attributes. Values can be:
     *
     * - `expires` - Either an integer specifying the expiration date from now on in days or a Date object. If a negative value is specified (e.g. a date in the past), the cookie will be deleted. If set to null or omitted, the cookie will be a session cookie and will not be retained when the the browser exits.
     * - `domain` - The domain name
     * - `path` - The value of the path atribute of the cookie (default: path of page that created the cookie).
     * - `secure` - If true, the secure attribute of the cookie will be set and the cookie transmission will require a secure protocol (like HTTPS).
     *
     * @return {String} the value of the cookie or {undefined} when setting the cookie.
     */
    jQuery.cookie = function(name, value, options) {
        if (typeof value != 'undefined') {
            // name and value given, set cookie
            options = options ||
            {};
            if (value === null) {
                value = '';
                options.expires = -1;
            }
	        // convert value to JSON string
            if (typeof value == 'object' && jQuery.toJSON) {
                value = jQuery.toJSON(value);
            }
            var expires = '';
	        // Set expiry
            if (options.expires && (typeof options.expires == 'number' || options.expires.toUTCString)) {
                var date;
                if (typeof options.expires == 'number') {
                    date = new Date();
                    date.setTime(date.getTime() + (options.expires * 24 * 60 * 60 * 1000));
                }
                else {
                    date = options.expires;
                }
                expires = '; expires=' + date.toUTCString(); // use expires attribute, max-age is not supported by IE
            }
            // CAUTION: Needed to parenthesize options.path and options.domain
            // in the following expressions, otherwise they evaluate to undefined
            // in the packed version for some reason...
            var path = options.path ? '; path=' + (options.path) : '';
            var domain = options.domain ? '; domain=' + (options.domain) : '';
            var secure = options.secure ? '; secure' : '';
	        // Set the cookie name=value;expires=;path=;domain=;secure-
            document.cookie = [name, '=', encodeURIComponent(value), expires, path, domain, secure].join('');
        }
        else { // only name given, get cookie
            var cookieValue = null;
            if (document.cookie && document.cookie != '') {
                var cookies = document.cookie.split(';');
                for (var i = 0; i < cookies.length; i++) {
                    var cookie = jQuery.trim(cookies[i]);
                    // Does this cookie string begin with the name we want?
                    if (cookie.substring(0, name.length + 1) == (name + '=')) {
	                    // Get the cookie value
                        cookieValue = decodeURIComponent(cookie.substring(name.length + 1));
                        break;
                    }
                }
            }
	        // Parse JSON from the cookie into an object
            if (jQuery.evalJSON && cookieValue && cookieValue.match(/^\s*\{/)) {
                try {
                    cookieValue = jQuery.evalJSON(cookieValue);
                }
                catch (e) {
                }
            }
            return cookieValue;
        }
    };

})(jQuery);
(function($){

/**
 * @function jQuery.fn.compare
 * @parent jQuery.compare
 *
 * Compare two elements and return a bitmask as a number representing the following conditions:
 *
 * - `000000` -> __0__: Elements are identical
 * - `000001` -> __1__: The nodes are in different documents (or one is outside of a document)
 * - `000010` -> __2__: #bar precedes #foo
 * - `000100` -> __4__: #foo precedes #bar
 * - `001000` -> __8__: #bar contains #foo
 * - `010000` -> __16__: #foo contains #bar
 *
 * You can check for any of these conditions using a bitwise AND:
 *
 *     if( $('#foo').compare($('#bar')) & 2 ) {
 *       console.log("#bar precedes #foo")
 *     }
 *
 * @param {HTMLElement|jQuery} element an element or jQuery collection to compare against.
 * @return {Number} A number representing a bitmask deatiling how the elements are positioned from each other.
 */

// See http://ejohn.org/blog/comparing-document-position/
jQuery.fn.compare = function(element){ //usually 
	try{
		// Firefox 3 throws an error with XUL - we can't use compare then
		element = element.jquery ? element[0] : element;
	}catch(e){
		return null;
	}

	// make sure we aren't coming from XUL element
	if (window.HTMLElement) {
		var s = HTMLElement.prototype.toString.call(element)
		if (s == '[xpconnect wrapped native prototype]' || s == '[object XULElement]' || s === '[object Window]') {
			return null;
		}
	}

	if(this[0].compareDocumentPosition){
		// For browsers that support it, use compareDocumentPosition
		// https://developer.mozilla.org/en/DOM/Node.compareDocumentPosition
		return this[0].compareDocumentPosition(element);
	}

	// this[0] contains element
	if(this[0] == document && element != document) return 8;

	var number =
			// this[0] contains element
			(this[0] !== element && this[0].contains(element) && 16) +
			// element contains this[0]
			(this[0] != element && element.contains(this[0]) && 8),
		docEl = document.documentElement;

	// Use the sourceIndex
	if(this[0].sourceIndex){
		// this[0] precedes element
		number += (this[0].sourceIndex < element.sourceIndex && 4)
		// element precedes foo[0]
		number += (this[0].sourceIndex > element.sourceIndex && 2)
		// The nodes are in different documents
		number += (this[0].ownerDocument !== element.ownerDocument ||
			(this[0] != docEl && this[0].sourceIndex <= 0 ) ||
			(element != docEl && element.sourceIndex <= 0 )) && 1
	}

	return number;
}

})(jQuery);
// XXX: This createTextRange causes zombie.js to fail.
//(function($){
//
//	$.fn.range =
///**
// * @function jQuery.fn.range
// * @parent jQuery.Range
// *
// * `$.fn.range` returns a new [jQuery.Range] instance for the first selected element.
// *
// *     $('#content').range() //-> range
// *
// * @return {$.Range} A $.Range instance for the selected element
// */
//function(){
//	return $.Range(this[0])
//}
//
//var convertType = function(type){
//	return  type.replace(/([a-z])([a-z]+)/gi, function(all,first,  next){
//			  return first+next.toLowerCase()
//			}).replace(/_/g,"");
//},
//// reverses things like START_TO_END into END_TO_START
//reverse = function(type){
//	return type.replace(/^([a-z]+)_TO_([a-z]+)/i, function(all, first, last){
//		return last+"_TO_"+first;
//	});
//},
//getWindow = function( element ) {
//	return element ? element.ownerDocument.defaultView || element.ownerDocument.parentWindow : window
//},
//bisect = function(el, start, end){
//	//split the start and end ... figure out who is touching ...
//	if(end-start == 1){
//		return
//	}
//},
//support = {};
///**
// * @Class jQuery.Range
// * @parent jQuery.Range
// *
// * Depending on the object passed, the selected text will be different.
// *
// * @param {TextRange|HTMLElement|Point} [range] An object specifiying a
// * range.  Depending on the object, the selected text will be different.  $.Range supports the
// * following types
// *
// *   - __undefined or null__ - returns a range with nothing selected
// *   - __HTMLElement__ - returns a range with the node's text selected
// *   - __Point__ - returns a range at the point on the screen.  The point can be specified like:
// *
// *         //client coordinates
// *         {clientX: 200, clientY: 300}
// *
// *         //page coordinates
// *         {pageX: 200, pageY: 300}
// *         {top: 200, left: 300}
// *
// *   - __TextRange__ a raw text range object.
// */
//
//$.Range = function(range){
//	// If it's called w/o new, call it with new!
//	if(this.constructor !== $.Range){
//		return new $.Range(range);
//	}
//	// If we are passed a jQuery-wrapped element, get the raw element
//	if(range && range.jquery){
//		range = range[0];
//	}
//	// If we have an element, or nothing
//	if(!range || range.nodeType){
//		// create a range
//		this.win = getWindow(range)
//		if(this.win.document.createRange){
//			this.range = this.win.document.createRange()
//		}else{
//			this.range = this.win.document.body.createTextRange()
//		}
//		// if we have an element, make the range select it
//		if(range){
//			this.select(range)
//		}
//	}
//	// if we are given a point
//	else if (range.clientX != null || range.pageX != null || range.left != null) {
//		this.moveToPoint(range);
//	}
//	// if we are given a touch event
//	else if (range.originalEvent && range.originalEvent.touches && range.originalEvent.touches.length) {
//		this.moveToPoint(range.originalEvent.touches[0])
//
//	}
//	// if we are a normal event
//	else if (range.originalEvent && range.originalEvent.changedTouches && range.originalEvent.changedTouches.length) {
//		this.moveToPoint(range.originalEvent.changedTouches[0])
//	}
//	// given a TextRange or something else?
//	else {
//		this.range = range;
//	}
//};
///**
// * @static
// */
//$.Range.
///**
// * `$.Range.current([element])` returns the currently selected range
// * (using [window.getSelection](https://developer.mozilla.org/en/nsISelection)).
// *
// *     var range = $.Range.current()
// *     range.start().offset // -> selection start offset
// *     range.end().offset // -> selection end offset
// *
// * @param {HTMLElement} [el] an optional element used to get selection for a given window.
// * @return {jQuery.Range} The range instance.
// */
//current = function(el){
//	var win = getWindow(el),
//		selection;
//	if(win.getSelection){
//		// If we can get the selection
//		selection = win.getSelection()
//		return new $.Range( selection.rangeCount ? selection.getRangeAt(0) : win.document.createRange())
//	} else {
//		// Otherwise use document.selection
//		return  new $.Range( win.document.selection.createRange() );
//	}
//};
//
//
//
//
//$.extend($.Range.prototype,
///** @prototype **/
//{
//	/**
//	 * `range.moveToPoint(point)` moves the range end and start position to a specific point.
//	 * A point can be specified like:
//	 *
//	 *      //client coordinates
//	 *      {clientX: 200, clientY: 300}
//	 *
//	 *      //page coordinates
//	 *      {pageX: 200, pageY: 300}
//	 *      {top: 200, left: 300}
//	 *
//	 * @param point The point to move the range to
//	 * @return {$.Range}
//	 */
//	moveToPoint : function(point){
//		var clientX = point.clientX, clientY = point.clientY
//		if(!clientX){
//			var off = scrollOffset();
//			clientX = (point.pageX || point.left || 0 ) - off.left;
//			clientY = (point.pageY || point.top || 0 ) - off.top;
//		}
//		if(support.moveToPoint){
//			this.range = $.Range().range
//			this.range.moveToPoint(clientX, clientY);
//			return this;
//		}
//
//
//		// it's some text node in this range ...
//		var parent = document.elementFromPoint(clientX, clientY);
//
//		//typically it will be 'on' text
//		for(var n=0; n < parent.childNodes.length; n++){
//			var node = parent.childNodes[n];
//			if(node.nodeType === 3 || node.nodeType === 4){
//				var range = $.Range(node),
//					length = range.toString().length;
//
//
//				// now lets start moving the end until the boundingRect is within our range
//				for(var i = 1; i < length+1; i++){
//					var rect = range.end(i).rect();
//					if(rect.left <= clientX && rect.left+rect.width >= clientX &&
//					  rect.top <= clientY && rect.top+rect.height >= clientY ){
//						range.start(i-1);
//						this.range = range.range;
//						return this;
//					}
//				}
//			}
//		}
//
//		// if not 'on' text, recursively go through and find out when we shift to next
//		// 'line'
//		var previous;
//		iterate(parent.childNodes, function(textNode){
//			var range = $.Range(textNode);
//			if(range.rect().top > point.clientY){
//				return false;
//			}else{
//				previous = range;
//			}
//		});
//
//		if(previous){
//			previous.start(previous.toString().length);
//			this.range = previous.range;
//		}else{
//			this.range = $.Range(parent).range
//		}
//	},
//
//	window : function(){
//		return this.win || window;
//	},
//	/**
//	 * `range.overlaps([elRange])` returns `true` if any portion of these two ranges overlap.
//	 *
//	 *     var foo = document.getElementById('foo');
//	 *
//	 *     $.Range(foo.childNodes[0]).overlaps(foo.childNodes[1]) //-> false
//	 *
//	 * @param {jQuery.Range} elRange The range to compare
//	 * @return {Boolean} true if part of the ranges overlap, false if otherwise.
//	 */
//	overlaps : function(elRange){
//		if(elRange.nodeType){
//			elRange = $.Range(elRange).select(elRange);
//		}
//		//if the start is within the element ...
//		var startToStart = this.compare("START_TO_START", elRange),
//			endToEnd = this.compare("END_TO_END", elRange)
//
//		// if we wrap elRange
//		if(startToStart <=0 && endToEnd >=0){
//			return true;
//		}
//		// if our start is inside of it
//		if( startToStart >= 0 &&
//			this.compare("START_TO_END", elRange) <= 0 )	{
//			return true;
//		}
//		// if our end is inside of elRange
//		if(this.compare("END_TO_START", elRange) >= 0 &&
//			endToEnd <= 0 )	{
//			return true;
//		}
//		return false;
//	},
//	/**
//	 * `range.collapse([toStart])` collapses a range to one of its boundary points.
//	 * See [range.collapse](https://developer.mozilla.org/en/DOM/range.collapse).
//	 *
//	 *     $('#foo').range().collapse()
//	 *
//	 * @param {Boolean} [toStart] true if to the start of the range, false if to the
//	 *  end.  Defaults to false.
//	 * @return {jQuery.Range} returns the range for chaining.
//	 */
//	collapse : function(toStart){
//		this.range.collapse(toStart === undefined ? true : toStart);
//		return this;
//	},
//	/**
//	 * `range.toString()` returns the text of the range.
//	 *
//	 *     currentText = $.Range.current().toString()
//	 *
//	 * @return {String} The text content of this range
//	 */
//	toString : function(){
//		return typeof this.range.text == "string"  ? this.range.text : this.range.toString();
//	},
//	/**
//	 * `range.start([start])` gets or sets the start of the range.
//	 *
//	 * If a value is not provided, start returns the range's starting container and offset like:
//	 *
//	 *     $('#foo').range().start()
//	 *     //-> {container: fooElement, offset: 0 }
//	 *
//	 * If a set value is provided, it can set the range.  The start of the range is set differently
//	 * depending on the type of set value:
//	 *
//	 *   - __Object__ - an object with the new starting container and offset like
//	 *
//	 *         $.Range().start({container:  $('#foo')[0], offset: 20})
//	 *
//	 *   - __Number__ - the new offset value.  The container is kept the same.
//	 *
//	 *   - __String__ - adjusts the offset by converting the string offset to a number and adding it to the current
//	 *     offset.  For example, the following moves the offset forward four characters:
//	 *
//	 *         $('#foo').range().start("+4")
//	 *
//	 * Note that `start` can return a text node. To get the containing element use this:
//	 *
//	 *     var startNode = range.start().container;
//	 *     if( startNode.nodeType === Node.TEXT_NODE ||
//	 *      startNode.nodeType === Node.CDATA_SECTION_NODE ) {
//	 *          startNode = startNode.parentNode;
//	 *     }
//	 *     $(startNode).addClass('highlight');
//	 *
//	 * @param {Object|String|Number} [set] a set value if setting the start of the range or nothing if reading it.
//	 * @return {jQuery.Range|Object} if setting the start, the range is returned for chaining, otherwise, the
//	 *   start offset and container are returned.
//	 */
//	start : function(set){
//		// return start
//		if(set === undefined){
//			if(this.range.startContainer){
//				return {
//					container : this.range.startContainer,
//					offset : this.range.startOffset
//				}
//			}else{
//				// Get the start parent element
//				var start = this.clone().collapse().parent();
//				// used to get the start element offset
//				var startRange = $.Range(start).select(start).collapse();
//				startRange.move("END_TO_START", this);
//				return {
//					container : start,
//					offset : startRange.toString().length
//				}
//			}
//		} else {
//			if (this.range.setStart) {
//				// supports setStart
//				if(typeof set == 'number'){
//					this.range.setStart(this.range.startContainer, set)
//				} else if(typeof set == 'string') {
//					var res = callMove(this.range.startContainer, this.range.startOffset, parseInt(set,10))
//					this.range.setStart(res.node, res.offset );
//				} else {
//					this.range.setStart(set.container, set.offset)
//				}
//			} else {
//				if(typeof set == "string"){
//					this.range.moveStart('character', parseInt(set,10))
//				} else {
//					// get the current end container
//					var container = this.start().container,
//						offset
//					if(typeof set == "number") {
//						offset = set
//					} else {
//						container = set.container
//						offset = set.offset
//					}
//					var newPoint = $.Range(container).collapse();
//					//move it over offset characters
//					newPoint.range.move(offset);
//					this.move("START_TO_START",newPoint);
//				}
//			}
//			return this;
//		}
//
//
//	},
//	/**
//	 * `range.end([end])` gets or sets the end of the range.
//	 * It takes similar options as [jQuery.Range::start start]:
//	 *
//	 * - __Object__ - an object with the new end container and offset like
//	 *
//	 *         $.Range().end({container:  $('#foo')[0], offset: 20})
//	 *
//	 * - __Number__ - the new offset value. The container is kept the same.
//	 *
//	 * - __String__ - adjusts the offset by converting the string offset to a number and adding it to the current
//	 * offset. For example, the following moves the offset forward four characters:
//	 *
//	 *         $('#foo').range().end("+4")
//	 *
//	 * Note that `end` can return a text node. To get the containing element use this:
//	 *
//	 *     var startNode = range.end().container;
//	 *     if( startNode.nodeType === Node.TEXT_NODE ||
//	 *      startNode.nodeType === Node.CDATA_SECTION_NODE ) {
//	 *          startNode = startNode.parentNode;
//	 *     }
//	 *     $(startNode).addClass('highlight');
//	 *
//	 * @param {Object|String|Number} [set] a set value if setting the end of the range or nothing if reading it.
//	 */
//	end : function(set){
//		// read end
//		if (set === undefined) {
//			if (this.range.startContainer) {
//				return {
//					container: this.range.endContainer,
//					offset: this.range.endOffset
//				}
//			}
//			else {
//				var
//					// Get the end parent element
//					end = this.clone().collapse(false).parent(),
//					// used to get the end elements offset
//					endRange = $.Range(end).select(end).collapse();
//				endRange.move("END_TO_END", this);
//				return {
//					container: end,
//					offset: endRange.toString().length
//				}
//			}
//		} else {
//			if (this.range.setEnd) {
//				if(typeof set == 'number'){
//					this.range.setEnd(this.range.endContainer, set)
//				} else if(typeof set == 'string') {
//					var res = callMove(this.range.endContainer, this.range.endOffset, parseInt(set,10))
//					this.range.setEnd(res.node, res.offset );
//				} else {
//					this.range.setEnd(set.container, set.offset)
//				}
//			} else {
//				if(typeof set == "string"){
//					this.range.moveEnd('character', parseInt(set,10));
//				} else {
//					// get the current end container
//					var container = this.end().container,
//						offset
//					if(typeof set == "number") {
//						offset = set
//					} else {
//						container = set.container
//						offset = set.offset
//					}
//					var newPoint = $.Range(container).collapse();
//					//move it over offset characters
//					newPoint.range.move(offset);
//					this.move("END_TO_START",newPoint);
//				}
//			}
//			return this;
//		}
//	},
//	/**
//	 * `range.parent()` returns the most common ancestor element of
//	 * the endpoints in the range. This will return a text element if the range is
//	 * within a text element. In this case, to get the containing element use this:
//	 *
//	 *     var parent = range.parent();
//	 *     if( parent.nodeType === Node.TEXT_NODE ||
//	 *      parent.nodeType === Node.CDATA_SECTION_NODE ) {
//	 *          parent = startNode.parentNode;
//	 *     }
//	 *     $(parent).addClass('highlight');
//	 *
//	 * @return {HTMLNode} the TextNode or HTMLElement
//	 * that fully contains the range
//	 */
//	parent : function(){
//		if(this.range.commonAncestorContainer){
//			return this.range.commonAncestorContainer;
//		} else {
//
//			var parentElement = this.range.parentElement(),
//				range = this.range;
//
//			// IE's parentElement will always give an element, we want text ranges
//			iterate(parentElement.childNodes, function(txtNode){
//				if($.Range(txtNode).range.inRange( range ) ){
//					// swap out the parentElement
//					parentElement = txtNode;
//					return false;
//				}
//			});
//
//			return parentElement;
//		}
//	},
//	/**
//	 * `range.rect([from])` returns the bounding rectangle of this range.
//	 *
//	 * @param {String} [from] - where the coordinates should be
//	 * positioned from.  By default, coordinates are given from the client viewport.
//	 * But if 'page' is given, they are provided relative to the page.
//	 *
//	 * @return {TextRectangle} - The client rects.
//	 */
//	rect : function(from){
//		var rect = this.range.getBoundingClientRect();
//		// for some reason in webkit this gets a better value
//		if(!rect.height && !rect.width){
//			rect = this.range.getClientRects()[0]
//		}
//		if(from === 'page'){
//			// Add the scroll offset
//			var off = scrollOffset();
//			rect = $.extend({}, rect);
//			rect.top += off.top;
//			rect.left += off.left;
//		}
//		return rect;
//	},
//	/**
//	 * `range.rects(from)` returns the client rects.
//	 *
//	 * @param {String} [from] how the rects coordinates should be given (viewport or page).  Provide 'page' for
//	 * rect coordinates from the page.
//	 * @return {Array} The client rects
//	 */
//	rects : function(from){
//		// order rects by size
//		var rects = $.map($.makeArray( this.range.getClientRects() ).sort(function(rect1, rect2){
//			return  rect2.width*rect2.height - rect1.width*rect1.height;
//		}), function(rect){
//			return $.extend({}, rect)
//		}),
//			i=0,j,
//			len = rects.length;
//
//		// safari returns overlapping client rects
//		//
//		//     - big rects can contain 2 smaller rects
//		//     - some rects can contain 0 - width rects
//		//     - we don't want these 0 width rects
//		while(i < rects.length){
//			var cur = rects[i],
//				found = false;
//
//			j = i+1;
//			while( j < rects.length ){
//				if( withinRect( cur, rects[j] ) ) {
//					if(!rects[j].width){
//						rects.splice(j,1)
//					} else {
//						found = rects[j];
//						break;
//					}
//				} else {
//					j++;
//				}
//			}
//
//
//			if(found){
//				rects.splice(i,1)
//			}else{
//				i++;
//			}
//
//		}
//		// safari will be return overlapping ranges ...
//		if(from == 'page'){
//			var off = scrollOffset();
//			return $.each(rects, function(ith, item){
//				item.top += off.top;
//				item.left += off.left;
//			})
//		}
//
//
//		return rects;
//	}
//
//});
//(function(){
//	//method branching ....
//	var fn = $.Range.prototype,
//		range = $.Range().range;
//
//	/**
//	 * @function compare
//	 *
//	 * `range.compare(type, compareRange)` compares one range to another range.
//	 *
//	 * ## Example
//	 *
//	 *     // compare the highlight element's start position
//	 *     // to the start of the current range
//	 *     $('#highlight')
//	 *         .range()
//	 *         .compare('START_TO_START', $.Range.current())
//	 *
//	 *
//	 *
//	 * @param {String} type Specifies the boundary of the
//	 * range and the <code>compareRange</code> to compare.
//	 *
//	 *   - `"START_TO_START"` - the start of the range and the start of compareRange
//	 *   - `"START_TO_END"` - the start of the range and the end of compareRange
//	 *   - `"END_TO_END"` - the end of the range and the end of compareRange
//	 *   - `"END_TO_START"` - the end of the range and the start of compareRange
//	 *
//	 * @param {$.Range} compareRange The other range
//	 * to compare against.
//	 * @return {Number} a number indicating if the range
//	 * boundary is before,
//	 * after, or equal to <code>compareRange</code>'s
//	 * boundary where:
//	 *
//	 *   - -1 - the range boundary comes before the compareRange boundary
//	 *   - 0 - the boundaries are equal
//	 *   - 1 - the range boundary comes after the compareRange boundary
//	 */
//	fn.compare = range.compareBoundaryPoints ?
//		function(type, range){
//			return this.range.compareBoundaryPoints(this.window().Range[reverse( type )], range.range)
//		}:
//		function(type, range){
//			return this.range.compareEndPoints(convertType(type), range.range)
//		}
//
//	/**
//	 * @function move
//	 *
//	 * `range.move([referenceRange])` moves the endpoints of a range relative to another range.
//	 *
//	 *     // Move the current selection's end to the
//	 *     // end of the #highlight element
//	 *     $.Range.current().move('END_TO_END',
//	 *       $('#highlight').range() )
//	 *
//	 *
//	 * @param {String} type a string indicating the ranges boundary point
//	 * to move to which referenceRange boundary point where:
//	 *
//	 *   - `"START_TO_START"` - the start of the range moves to the start of referenceRange
//	 *   - `"START\_TO\_END"` - the start of the range move to the end of referenceRange
//	 *   - `"END_TO_END"` - the end of the range moves to the end of referenceRange
//	 *   - `"END_TO_START"` - the end of the range moves to the start of referenceRange
//	 *
//	 * @param {jQuery.Range} referenceRange
//	 * @return {jQuery.Range} the original range for chaining
//	 */
//	fn.move = range.setStart ?
//		function(type, range){
//
//			var rangesRange = range.range;
//			switch(type){
//				case "START_TO_END" :
//					this.range.setStart(rangesRange.endContainer, rangesRange.endOffset)
//					break;
//				case "START_TO_START" :
//					this.range.setStart(rangesRange.startContainer, rangesRange.startOffset)
//					break;
//				case "END_TO_END" :
//					this.range.setEnd(rangesRange.endContainer, rangesRange.endOffset)
//					break;
//				case "END_TO_START" :
//					this.range.setEnd(rangesRange.startContainer, rangesRange.startOffset)
//					break;
//			}
//
//			return this;
//		}:
//		function(type, range){
//			this.range.setEndPoint(convertType(type), range.range)
//			return this;
//		};
//	var cloneFunc = range.cloneRange ? "cloneRange" : "duplicate",
//		selectFunc = range.selectNodeContents ? "selectNodeContents" : "moveToElementText";
//
//	fn.
//	/**
//	 * `range.clone()` clones the range and returns a new $.Range
//	 * object:
//	 *
//	 *      var range = new $.Range(document.getElementById('text'));
//	 *      var newRange = range.clone();
//	 *      range.start('+2');
//	 *      range.select();
//	 *
//	 * @return {jQuery.Range} returns the range as a $.Range.
//	 */
//	clone = function(){
//		return $.Range( this.range[cloneFunc]() );
//	};
//
//	fn.
//	/**
//	 * @function
//	 *
//	 * `range.select([el])` selects an element with this range.  If nothing
//	 * is provided, makes the current range appear as if the user has selected it.
//	 *
//	 * This works with text nodes. For example with:
//	 *
//	 *      <div id="text">This is a text</div>
//	 *
//	 * $.Range can select `is a` like this:
//	 *
//	 *      var range = new $.Range(document.getElementById('text'));
//	 *      range.start('+5');
//	 *      range.end('-5');
//	 *      range.select();
//	 *
//	 * @param {HTMLElement} [el] The element in which this range should be selected
//	 * @return {jQuery.Range} the range for chaining.
//	 */
//	select = range.selectNodeContents ? function(el){
//		if(!el){
//			var selection = this.window().getSelection();
//			selection.removeAllRanges();
//			selection.addRange(this.range);
//		}else {
//			this.range.selectNodeContents(el);
//		}
//		return this;
//	} : function(el){
//		if(!el){
//			this.range.select()
//		} else if(el.nodeType === 3){
//			//select this node in the element ...
//			var parent = el.parentNode,
//				start = 0,
//				end;
//			iterate(parent.childNodes, function(txtNode){
//				if(txtNode === el){
//					end = start + txtNode.nodeValue.length;
//					return false;
//				} else {
//					start = start + txtNode.nodeValue.length
//				}
//			})
//			this.range.moveToElementText(parent);
//
//			this.range.moveEnd('character', end - this.range.text.length)
//			this.range.moveStart('character', start);
//		} else {
//			this.range.moveToElementText(el);
//		}
//		return this;
//	};
//
//})();
//
//
//// helpers  -----------------
//
//// iterates through a list of elements, calls cb on every text node
//// if cb returns false, exits the iteration
//var iterate = function(elems, cb){
//	var elem, start;
//	for (var i = 0; elems[i]; i++) {
//		elem = elems[i];
//		// Get the text from text nodes and CDATA nodes
//		if (elem.nodeType === 3 || elem.nodeType === 4) {
//			if (cb(elem) === false) {
//				return false;
//			}
//			// Traverse everything else, except comment nodes
//		}
//		else
//			if (elem.nodeType !== 8) {
//				if (iterate(elem.childNodes, cb) === false) {
//					return false;
//				}
//			}
//	}
//
//},
//isText = function(node){
//	return node.nodeType === 3 || node.nodeType === 4
//},
//iteratorMaker = function(toChildren, toNext){
//	return function( node, mustMoveRight ) {
//		// first try down
//		if(node[toChildren] && !mustMoveRight){
//			return isText(node[toChildren]) ?
//				node[toChildren] :
//			 	arguments.callee(node[toChildren])
//		} else if(node[toNext]) {
//			return isText(node[toNext]) ?
//				node[toNext] :
//			 	arguments.callee(node[toNext])
//		} else if(node.parentNode){
//			return arguments.callee(node.parentNode, true)
//		}
//	}
//},
//getNextTextNode = iteratorMaker("firstChild","nextSibling"),
//getPrevTextNode = iteratorMaker("lastChild","previousSibling"),
//callMove = function(container, offset, howMany){
//	if(isText(container)){
//		return move(container, offset+howMany)
//	} else {
//		return container.childNodes[offset] ?
//			move(container.childNodes[offset] , howMany) :
//			move(container.lastChild, howMany , true)
//		return
//	}
//},
//move = function(from, howMany){
//	var mover = howMany < 0 ?
//		getPrevTextNode : getNextTextNode;
//
//	howMany = Math.abs(howMany);
//
//	if(!isText(from)){
//		from = mover(from)
//	}
//	while(from && howMany >= from.nodeValue.length){
//		hasMany  = howMany- from.nodeValue.length;
//		from = mover(from)
//	}
//	return {
//		node: from,
//		offset: mover === getNextTextNode ?
//			howMany :
//			from.nodeValue.length - howMany
//	}
//},
//supportWhitespace,
//isWhitespace = function(el){
//	if(supportWhitespace == null){
//		supportWhitespace = 'isElementContentWhitespace' in el;
//	}
//	return (supportWhitespace? el.isElementContentWhitespace :
//			(el.nodeType === 3 && '' == el.data.trim()));
//
//},
//// if a point is within a rectangle
//within = function(rect, point){
//
//	return rect.left <= point.clientX && rect.left + rect.width >= point.clientX &&
//	rect.top <= point.clientY &&
//	rect.top + rect.height >= point.clientY
//},
//// if a rectangle is within another rectangle
//withinRect = function(outer, inner){
//	return within(outer, {
//		clientX: inner.left,
//		clientY: inner.top
//	}) && //top left
//	within(outer, {
//		clientX: inner.left + inner.width,
//		clientY: inner.top
//	}) && //top right
//	within(outer, {
//		clientX: inner.left,
//		clientY: inner.top + inner.height
//	}) && //bottom left
//	within(outer, {
//		clientX: inner.left + inner.width,
//		clientY: inner.top + inner.height
//	}) //bottom right
//},
//// gets the scroll offset from a window
//scrollOffset = function( win){
//	var win = win ||window;
//		doc = win.document.documentElement, body = win.document.body;
//
//	return {
//		left: (doc && doc.scrollLeft || body && body.scrollLeft || 0) + (doc.clientLeft || 0),
//		top: (doc && doc.scrollTop || body && body.scrollTop || 0) + (doc.clientTop || 0)
//	};
//};
//
//
//support.moveToPoint = !!$.Range().range.moveToPoint
//
//
//})(jQuery);
//(function($){
//
//var getWindow = function( element ) {
//	return element ? element.ownerDocument.defaultView || element.ownerDocument.parentWindow : window
//},
//// A helper that uses range to abstract out getting the current start and endPos.
//getElementsSelection = function(el, win){
//	// get a copy of the current range and a range that spans the element
//	var current = $.Range.current(el).clone(),
//		entireElement = $.Range(el).select(el);
//	// if there is no overlap, there is nothing selected
//	if(!current.overlaps(entireElement)){
//		return null;
//	}
//	// if the current range starts before our element
//	if(current.compare("START_TO_START", entireElement) < 1){
//		// the selection within the element begins at 0
//		startPos = 0;
//		// move the current range to start at our element
//		current.move("START_TO_START",entireElement);
//	}else{
//		// Make a copy of the element's range.
//		// Move it's end to the start of the selected range
//		// The length of the copy is the start of the selected
//		// range.
//		fromElementToCurrent =entireElement.clone();
//		fromElementToCurrent.move("END_TO_START", current);
//		startPos = fromElementToCurrent.toString().length
//	}
//	
//	// If the current range ends after our element
//	if(current.compare("END_TO_END", entireElement) >= 0){
//		// the end position is the last character
//		endPos = entireElement.toString().length
//	}else{
//		// otherwise, it's the start position plus the current range
//		// TODO: this doesn't seem like it works if current
//		// extends to the left of the element.
//		endPos = startPos+current.toString().length
//	}
//	return {
//		start: startPos,
//		end : endPos,
//		width : endPos - startPos
//	};
//},
//// Text selection works differently for selection in an input vs
//// normal html elements like divs, spans, and ps.
//// This function branches between the various methods of getting the selection.
//getSelection = function(el){
//	var win = getWindow(el);
//	
//	// `selectionStart` means this is an input element in a standards browser.
//	if (el.selectionStart !== undefined) {
//
//		if(document.activeElement 
//		 	&& document.activeElement != el 
//			&& el.selectionStart == el.selectionEnd 
//			&& el.selectionStart == 0){
//			return {start: el.value.length, end: el.value.length, width: 0};
//		}
//		return  {start: el.selectionStart, end: el.selectionEnd, width: el.selectionEnd - el.selectionStart};
//	} 
//	// getSelection means a 'normal' element in a standards browser.
//	else if(win.getSelection){
//		return getElementsSelection(el, win)
//	} else{
//		// IE will freak out, where there is no way to detect it, so we provide a callback if it does.
//		try {
//			// The following typically works for input elements in IE:
//			if (el.nodeName.toLowerCase() == 'input') {
//				var real = getWindow(el).document.selection.createRange(), 
//					r = el.createTextRange();
//				r.setEndPoint("EndToStart", real);
//				
//				var start = r.text.length
//				return {
//					start: start,
//					end: start + real.text.length,
//					width: real.text.length
//				}
//			}
//			// This works on textareas and other elements
//			else {
//				var res = getElementsSelection(el,win)
//				if(!res){
//					return res;
//				}
//				// we have to clean up for ie's textareas which don't count for 
//				// newlines correctly
//				var current = $.Range.current().clone(),
//					r2 = current.clone().collapse().range,
//					r3 = current.clone().collapse(false).range;
//				
//				r2.moveStart('character', -1)
//				r3.moveStart('character', -1)
//				// if we aren't at the start, but previous is empty, we are at start of newline
//				if (res.startPos != 0 && r2.text == "") {
//					res.startPos += 2;
//				}
//				// do a similar thing for the end of the textarea
//				if (res.endPos != 0 && r3.text == "") {
//					res.endPos += 2;
//				}
//				
//				return res
//			}
//		}catch(e){
//			return {start: el.value.length, end: el.value.length, width: 0};
//		}
//	} 
//},
//// Selects text within an element.  Depending if it's a form element or
//// not, or a standards based browser or not, we do different things.
//select = function( el, start, end ) {
//	var win = getWindow(el);
//	// IE behaves bad even if it sorta supports
//	// getSelection so we have to try the IE methods first. barf.
//	if(el.setSelectionRange){
//		if(end === undefined){
//            el.focus();
//            el.setSelectionRange(start, start);
//		} else {
//			el.select();
//			el.selectionStart = start;
//			el.selectionEnd = end;
//		}
//	} else if (el.createTextRange) {
//		var r = el.createTextRange();
//		r.moveStart('character', start);
//		end = end || start;
//		r.moveEnd('character', end - el.value.length);
//		
//		r.select();
//	} else if(win.getSelection){
//		var	doc = win.document,
//			sel = win.getSelection(),
//			range = doc.createRange(),
//			ranges = [start,  end !== undefined ? end : start];
//		getCharElement([el],ranges);
//		range.setStart(ranges[0].el, ranges[0].count);
//		range.setEnd(ranges[1].el, ranges[1].count);
//		
//		// removeAllRanges is necessary for webkit
//        sel.removeAllRanges();
//        sel.addRange(range);
//		
//	} else if(win.document.body.createTextRange){ //IE's weirdness
//		var range = document.body.createTextRange();
//		range.moveToElementText(el);
//		range.collapse()
//		range.moveStart('character', start)
//		range.moveEnd('character', end !== undefined ? end : start)
//        range.select();
//	}
//
//},
//// If one of the range values is within start and len, replace the range
//// value with the element and its offset.
//replaceWithLess = function(start, len, range, el){
//	if(typeof range[0] === 'number' && range[0] < len){
//			range[0] = {
//				el: el,
//				count: range[0] - start
//			};
//	}
//	if(typeof range[1] === 'number' && range[1] <= len){
//			range[1] = {
//				el: el,
//				count: range[1] - start
//			};;
//	}
//},
//getCharElement = function( elems , range, len ) {
//	var elem,
//		start;
//	
//	len = len || 0;
//	for ( var i = 0; elems[i]; i++ ) {
//		elem = elems[i];
//		// Get the text from text nodes and CDATA nodes
//		if ( elem.nodeType === 3 || elem.nodeType === 4 ) {
//			start = len
//			len += elem.nodeValue.length;
//			//check if len is now greater than what's in counts
//			replaceWithLess(start, len, range, elem ) 
//		// Traverse everything else, except comment nodes
//		} else if ( elem.nodeType !== 8 ) {
//			len = getCharElement( elem.childNodes, range, len );
//		}
//	}
//	return len;
//};
///**
// * @parent jQuery.selection
// * @function jQuery.fn.selection
// *
// * Set or retrieve the currently selected text range. It works on all elements:
// *
// *      $('#text').selection(8, 12)
// *      $('#text').selection() // -> { start : 8, end : 12, width: 4 }
// *
// * @param {Number} [start] Start position of the selection range
// * @param {Number} [end] End position of the selection range
// * @return {Object|jQuery} Returns either the jQuery object when setting the selection or
// * an object containing
// *
// * - __start__ - The number of characters from the start of the element to the start of the selection.
// * - __end__ - The number of characters from the start of the element to the end of the selection.
// * - __width__ - The width of the selection range.
// *
// * when no arguments are passed.
// */
//$.fn.selection = function(start, end){
//	if(start !== undefined){
//		return this.each(function(){
//			select(this, start, end)
//		})
//	}else{
//		return getSelection(this[0])
//	}
//};
//// for testing
//$.fn.selection.getCharElement = getCharElement;
//
//})(jQuery);
(function($){
	var keymap = {},
		reverseKeyMap = {},
		currentBrowser = jQuery.uaMatch(navigator.userAgent).browser;
		
	/**
	 * @hide
	 * @parent jQuery.Event.prototype.key
	 * 
	 * Allows you to set alternate key maps or overwrite existing key codes.
	 * For example::
	 * 
	 *     $.event.key({"~" : 177});
	 * 
	 * @param {Object} map A map of character - keycode pairs.
	 */
	$.event.key = function(browser, map){
		if(browser === undefined) {
			return keymap;
		}

		if(map === undefined) {
			map = browser;
			browser = currentBrowser;
		}

		// extend the keymap
		if(!keymap[browser]) {
			keymap[browser] = {};
		}
		$.extend(keymap[browser], map);
		// and also update the reverse keymap
		if(!reverseKeyMap[browser]) {
			reverseKeyMap[browser] = {};
		}
		for(var name in map){
			reverseKeyMap[browser][map[name]] = name;
		}
	};
	
	$.event.key({
		// backspace
		'\b':'8',
		
		// tab
		'\t':'9',
		
		// enter
		'\r':'13',
		
		// special
		'shift':'16','ctrl':'17','alt':'18',
		
		// others
		'pause-break':'19',
		'caps':'20',
		'escape':'27',
		'num-lock':'144',
		'scroll-lock':'145',
		'print' : '44',
		
		// navigation
		'page-up':'33','page-down':'34','end':'35','home':'36',
		'left':'37','up':'38','right':'39','down':'40','insert':'45','delete':'46',
		
		// normal characters
		' ':'32',
		'0':'48','1':'49','2':'50','3':'51','4':'52','5':'53','6':'54','7':'55','8':'56','9':'57',
		'a':'65','b':'66','c':'67','d':'68','e':'69','f':'70','g':'71','h':'72','i':'73','j':'74','k':'75','l':'76','m':'77',
		'n':'78','o':'79','p':'80','q':'81','r':'82','s':'83','t':'84','u':'85','v':'86','w':'87','x':'88','y':'89','z':'90',
		// normal-characters, numpad
		'num0':'96','num1':'97','num2':'98','num3':'99','num4':'100','num5':'101','num6':'102','num7':'103','num8':'104','num9':'105',
		'*':'106','+':'107','-':'109','.':'110',
		// normal-characters, others
		'/':'111',
		';':'186',
		'=':'187',
		',':'188',
		'-':'189',
		'.':'190',
		'/':'191',
		'`':'192',
		'[':'219',
		'\\':'220',
		']':'221',
		"'":'222',
		
		// ignore these, you shouldn't use them
		'left window key':'91','right window key':'92','select key':'93',
		
		
		'f1':'112','f2':'113','f3':'114','f4':'115','f5':'116','f6':'117',
		'f7':'118','f8':'119','f9':'120','f10':'121','f11':'122','f12':'123'
	});
	
	/**
	 * @parent jQuery.event.key
	 * @plugin jquery/event/key
	 * @function jQuery.Event.prototype.keyName
	 *
	 * Returns a string representation of the key pressed:
	 *
	 *      $("input").on('keypress', function(ev){
	 *          if(ev.keyName() == 'ctrl') {
	 *              $(this).addClass('highlight');
	 *          }
	 *      });
	 *
	 * The key names mapped by default can be found in the [jQuery.event.key jQuery.event.key overview].
	 *
	 * @return {String} The string representation of of the key pressed.
	 */
	jQuery.Event.prototype.keyName  = function(){
		var event = this,
			test = /\w/,
			// It can be either keyCode or charCode.
			// Look both cases up in the reverse key map and converted to a string
			key_Key =  reverseKeyMap[currentBrowser][(event.keyCode || event.which)+""],
			char_Key =  String.fromCharCode(event.keyCode || event.which),
			key_Char =  event.charCode && reverseKeyMap[currentBrowser][event.charCode+""],
			char_Char = event.charCode && String.fromCharCode(event.charCode);
		
		if( char_Char && test.test(char_Char) ) {
			// string representation of event.charCode
			return char_Char.toLowerCase()
		}
		if( key_Char && test.test(key_Char) ) {
			// reverseKeyMap representation of event.charCode
			return char_Char.toLowerCase()
		}
		if( char_Key && test.test(char_Key) ) {
			// string representation of event.keyCode
			return char_Key.toLowerCase()
		}
		if( key_Key && test.test(key_Key) ) {
			// reverseKeyMap representation of event.keyCode
			return key_Key.toLowerCase()
		}

		if (event.type == 'keypress'){
			// keypress doesn't capture everything
			return event.keyCode ? String.fromCharCode(event.keyCode) : String.fromCharCode(event.which)
		}

		if (!event.keyCode && event.which) {
			// event.which
			return String.fromCharCode(event.which)
		}

		// default
		return reverseKeyMap[currentBrowser][event.keyCode+""]
	}
	
	
})(jQuery)
