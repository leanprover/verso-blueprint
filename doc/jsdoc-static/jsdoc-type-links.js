(function () {
  "use strict";

  var typeNames = (window.blueprintJSDocTypeNames || []).slice();
  if (typeNames.length === 0) return;

  typeNames.sort(function (left, right) {
    return right.length - left.length;
  });

  var links = Object.create(null);
  typeNames.forEach(function (name) {
    links[name] = "module-blueprint-api-types.html#~" + name;
  });

  var typePattern = new RegExp("\\b(" + typeNames.join("|") + ")\\b", "g");

  function hasTypeName(text) {
    typePattern.lastIndex = 0;
    return typePattern.test(text);
  }

  function linkTextNode(node) {
    var text = node.nodeValue || "";
    if (!hasTypeName(text)) return;

    var fragment = document.createDocumentFragment();
    var lastIndex = 0;
    typePattern.lastIndex = 0;

    text.replace(typePattern, function (match, typeName, offset) {
      if (offset > lastIndex) {
        fragment.appendChild(document.createTextNode(text.slice(lastIndex, offset)));
      }

      var link = document.createElement("a");
      link.href = links[typeName];
      link.textContent = match;
      fragment.appendChild(link);
      lastIndex = offset + match.length;
      return match;
    });

    if (lastIndex < text.length) {
      fragment.appendChild(document.createTextNode(text.slice(lastIndex)));
    }

    node.parentNode.replaceChild(fragment, node);
  }

  function linkTypeNames() {
    var roots = document.querySelectorAll(".type-signature, .param-type, td.type");
    roots.forEach(function (root) {
      var nodes = [];
      var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
        acceptNode: function (node) {
          if (!hasTypeName(node.nodeValue || "")) return NodeFilter.FILTER_REJECT;
          if (node.parentElement && node.parentElement.closest("a")) {
            return NodeFilter.FILTER_REJECT;
          }
          return NodeFilter.FILTER_ACCEPT;
        }
      });

      while (walker.nextNode()) nodes.push(walker.currentNode);
      nodes.forEach(linkTextNode);
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", linkTypeNames);
  } else {
    linkTypeNames();
  }
})();
