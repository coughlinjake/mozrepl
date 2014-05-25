// Prints all the direct (or prototype chain to the `depth`:ed level) properties
// of "at" in the repl, optionally matching regexp `re` only -- ordered by type.
function peek(at, depth, re, typeRe) {

  function lsKeys(data, level, matches, total) {
    var types = [], type, header = '';
    for (type in data) {
      if (!data.hasOwnProperty(type)) continue;
      types.push(type);
    }

    if (matches !== total)
      header = matches +'/'+ total +' matches';
    if (level)
      header += (header ? ' on ': '') +'prototype ancestor '+ level +':';
    if (header) repl.print('\n' + header);

    types.sort().forEach(function ls(type) {
      repl.print(type +':\n  '+ (data[type].sort().join('\n  ')));
    });
  }

  if ('number' !== typeof depth) {
    typeRe = re;
    re = depth;
    depth = 0;
  }

  var l = 0, self = at, self_type = 'self ['+ typeOf(self) +']', intp = /^\d+$/;
  do {

    var type = typeOf(at);
    repl.print(type + (/^(?:number|string)$/.test(type) ? ': '+ at : ''));
    if (/^(?:number|string|null|undefined)$/.test(type)) return;

    // data[type] = [key, key, ...]
    var data = {}, key, val, count = 0, matches = 0;
    for (key in at) {
      if (!at.hasOwnProperty(key)) continue;
      if (self_type === 'self [object Array]' && intp.test(key)) continue;
      ++count;
      if (re && !re.test(key)) continue;
      ++matches;

      try {
        val = at[key];
        type = typeOf(val);
      } catch (e) {
        type = 'unknown';
      }
      if (typeRe && !typeRe.test(type)) {
        --matches;
        continue;
      }

      if (self === val)
        type = self_type;
      else if ('boolean' === type || 'number' === type)
        key += ' = '+ val;
      else if ('string' === type)
        if (val.length < 40)
          key += ' = '+ uneval(val);
        else
          key += ' = String(/* '+ val.length +' chars */)';
      data[type] = (data[type] || []).concat(key);
    }

    lsKeys(data, l++, matches, count);

  } while (depth-- && (at.__proto__ !== at) && (at = at.__proto__));
}

// Reports useful types such as "string", "number", "null", "native function",
// "function", "undefined", "object Object", "object Array", "object RegExp",
// and the special identity type "self[whatever the type of `at` itself was]"
function typeOf(x) {
  var k, t = null == x ? null === x ? 'null' : 'undefined' : typeof x;

  if ('function' === t)
    return /\{\x5Bnative code\x5D\}$/.test(x.toSource()) ? 'native ' + t : t;

  if ('object' !== t || !(k = Object.prototype.toString.call(x)) ||
      !(k = /^\x5Bobject (.*)\x5D$/.exec(k)) || !(k = k[1]))
    return t; // number, string, null, undefined, super-weird "object"s

  // /^(Array|Object|RegExp)$/.test(k) ? k :
  return t +' '+ k; // typed objects
}

// Peeks at JSONable properties only. Remember to pass an Infinity depth, if you
// want everything that serializing the object would pick up.
function peekJSON(o, depth, re) {
  peek(o, depth || 0, re,
       /^(?:boolean|number|string|object Object|object Array|null)$/);
}

function peekUnJSON(o, depth, re) {
  peek(o, depth || 0, re,
       /^(?!(boolean|number|string|object Object|object Array|null)$)/);
}

// Peeks at members of type object only. If arg 0 is a RegExp, only peek at the
// objects of a type matching that RegExp; ie peekObj(/^nsXPC/, this) will only
// list the nsXPCComponents, nsXPCComponents_Classes, nsXPC... type members.
function peekObj(o, depth, re, typeRe) {
  if ('string' === typeof o || 'object RegExp' === typeOf(o)) {
    var flags = o.ignoreCase === true ? 'i' : '';
    if ('string' != typeof o) o = o.toSource().replace(/^\/|\/[a-z]*$/g, '');
    o = '^object '+ (o.replace(/^(?!\^)/, '.*').replace(/^\^/, ''));
    return peekObj(depth, re, typeRe, new RegExp(o, flags));
  }
  return peek(o, depth || 0, re, typeRe || /^object /);
}

function peekFn(o, depth, re) {
  peek(o, depth || 0, re, /^(?!native )?function$/);
}

function peekNative(o, depth, re) {
  peek(o, depth || 0, re, /^native function$/);
}
