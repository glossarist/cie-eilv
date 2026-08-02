import Plurimath from '@plurimath/plurimath';

window.PlurimathRenderer = {
  ready: true,
  toMathML: function(expr, format) {
    try {
      var p = new Plurimath(expr, format || 'asciimath');
      return p.toMathml();
    } catch(e) {
      return null;
    }
  },
  toHtml: function(expr, format) {
    try {
      var p = new Plurimath(expr, format || 'asciimath');
      return p.toHtml();
    } catch(e) {
      return null;
    }
  }
};
window.dispatchEvent(new Event('plurimath-ready'));
