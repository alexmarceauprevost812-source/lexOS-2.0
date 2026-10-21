/* LexOS · Couleurs du code (coloration syntaxique maison, sans dépendance) */
"use strict";

const LANGS = {
  py: "python", python: "python", js: "js", mjs: "js", cjs: "js", javascript: "js", ts: "js", tsx: "js", jsx: "js", typescript: "js",
  json: "json", html: "html", htm: "html", xml: "html", svg: "html", vue: "html", css: "css", scss: "css",
  sh: "bash", bash: "bash", shell: "bash", zsh: "bash", console: "bash", terminal: "bash",
  md: "md", markdown: "md", txt: "texte", text: "texte",
  //  ALEX : « ajouter de la couleur au Codex ». Ces langages s'affichaient
  //  en texte nu : ils ont maintenant leurs règles (ou les règles communes).
  rs: "rust", rust: "rust", go: "go", golang: "go",
  c: "c", h: "c", cpp: "c", cc: "c", hpp: "c", cxx: "c", java: "c", kt: "c", kotlin: "c", cs: "c", csharp: "c", swift: "c", dart: "c",
  php: "php", rb: "ruby", ruby: "ruby", lua: "lua", sql: "sql", psql: "sql", sqlite: "sql",
  yaml: "yaml", yml: "yaml", toml: "ini", ini: "ini", conf: "ini", cfg: "ini", env: "ini", desktop: "ini", service: "ini",
  diff: "diff", patch: "diff", dockerfile: "docker", makefile: "bash", mk: "bash",
};
const MOTS = {
  python: "and|as|assert|async|await|break|class|continue|def|del|elif|else|except|finally|for|from|global|if|import|in|is|lambda|nonlocal|not|or|pass|raise|return|try|while|with|yield|match|case",
  js: "await|async|break|case|catch|class|const|continue|debugger|default|delete|do|else|export|extends|finally|for|from|function|if|import|in|instanceof|let|new|of|return|static|super|switch|this|throw|try|typeof|var|void|while|with|yield|interface|type|enum|implements",
  bash: "if|then|else|elif|fi|for|while|do|done|case|esac|in|function|return|export|local|sudo|cd|echo|exit|source|set|shift|trap|readonly|declare|unset|printf|read",
  rust: "as|async|await|break|const|continue|crate|dyn|else|enum|extern|fn|for|if|impl|in|let|loop|match|mod|move|mut|pub|ref|return|static|struct|super|trait|type|unsafe|use|where|while",
  go: "break|case|chan|const|continue|default|defer|else|fallthrough|for|func|go|goto|if|import|interface|map|package|range|return|select|struct|switch|type|var",
  c: "auto|break|case|catch|char|class|const|continue|default|delete|do|double|else|enum|extends|extern|final|finally|float|for|fun|goto|if|implements|import|include|define|ifdef|ifndef|endif|pragma|inline|int|interface|long|namespace|new|override|package|private|protected|public|register|return|short|signed|sizeof|static|struct|switch|template|this|throw|throws|try|typedef|typename|union|unsigned|using|val|var|virtual|void|volatile|while|when|object|data|let|func|guard|async|await",
  php: "abstract|and|array|as|break|case|catch|class|clone|const|continue|declare|default|do|echo|else|elseif|empty|endif|endforeach|extends|final|finally|fn|for|foreach|function|global|if|implements|include|include_once|instanceof|interface|isset|list|match|namespace|new|or|print|private|protected|public|require|require_once|return|static|switch|throw|trait|try|unset|use|var|while|yield",
  ruby: "alias|and|begin|break|case|class|def|defined|do|else|elsif|end|ensure|for|if|in|module|next|not|or|redo|rescue|retry|return|super|then|undef|unless|until|when|while|yield|require|attr_accessor|attr_reader|puts",
  lua: "and|break|do|else|elseif|end|for|function|goto|if|in|local|not|or|repeat|return|then|until|while",
  sql: "select|from|where|insert|into|values|update|set|delete|create|table|drop|alter|add|index|view|join|left|right|inner|outer|full|on|as|and|or|not|null|is|in|like|between|group|by|order|asc|desc|limit|offset|having|distinct|union|all|primary|key|foreign|references|default|unique|check|constraint|case|when|then|else|end|exists|returning|begin|commit|rollback|with|integer|int|text|varchar|boolean|real|date|timestamp|serial|bigint",
  docker: "FROM|RUN|CMD|LABEL|EXPOSE|ENV|ADD|COPY|ENTRYPOINT|VOLUME|USER|WORKDIR|ARG|ONBUILD|STOPSIGNAL|HEALTHCHECK|SHELL|AS",
};
const SPECIAUX = {
  python: "True|False|None|self|cls|print|len|range|open|str|int|float|list|dict|set|tuple|isinstance|super|enumerate|zip|map|filter|sorted|input|type|Exception",
  js: "true|false|null|undefined|NaN|Infinity|console|document|window|JSON|Math|Promise|Array|Object|String|Number|Map|Set|fetch|require|module",
  commun: "true|false|null|nil|None|True|False|NULL|nullptr|undefined|self|this|Self|Some|Ok|Err|println|printf|fmt|std|String|Vec|Option|Result|bool|i32|i64|u8|u32|u64|usize|f32|f64|str",
};

function _regles(lang) {
  const k = (s) => new RegExp(`\\b(?:${s})\\b`);
  switch (lang) {
    case "python": return [
      ["com", /#[^\n]*/], ["chaine", /(?:[rRbBfFuU]{0,2})(?:"""[\s\S]*?(?:"""|$)|'''[\s\S]*?(?:'''|$)|"(?:\\.|[^"\\\n])*"?|'(?:\\.|[^'\\\n])*'?)/],
      ["deco", /@[\w.]+/], ["defnom", /(?<=\b(?:def|class)\s+)[A-Za-z_]\w*/], ["mot", k(MOTS.python)], ["soi", /\b(?:self|cls)\b/], ["special", k(SPECIAUX.python)],
      ["nombre", /\b(?:0x[\da-fA-F_]+|\d[\d_]*(?:\.\d+)?(?:e[+-]?\d+)?j?)\b/], ["constante", /\b[A-Z][A-Z0-9_]{2,}\b/], ["fonction", /\b[A-Za-z_]\w*(?=\s*\()/], ["classe", /\b[A-Z][A-Za-z0-9_]+\b/],
      ["propriete", /(?<=\.)[A-Za-z_]\w*/], ["op", /->|:=|==|!=|<=|>=|\*\*|\/\/|[+\-*/%=<>!&|^~]/], ["par", /[()[\]{}]/]];
    case "js": return [
      ["com", /\/\/[^\n]*|\/\*[\s\S]*?(?:\*\/|$)/], ["chaine", /`(?:\\.|[^`\\])*`?|"(?:\\.|[^"\\\n])*"?|'(?:\\.|[^'\\\n])*'?/],
      ["mot", k(MOTS.js)], ["special", k(SPECIAUX.js)], ["nombre", /\b(?:0x[\da-fA-F]+|\d[\d_]*(?:\.\d+)?(?:e[+-]?\d+)?n?)\b/],
      ["constante", /\b[A-Z][A-Z0-9_]{2,}\b/], ["fonction", /\b[A-Za-z_$][\w$]*(?=\s*\()/], ["classe", /\b[A-Z][A-Za-z0-9_$]+\b/],
      ["propriete", /(?<=\.)[A-Za-z_$][\w$]*/], ["op", /=>|===|!==|&&|\|\||\?\?|\.\.\.|[+\-*/%=<>!&|^~?:]/], ["par", /[()[\]{}]/]];
    case "json": return [["cle", /"(?:\\.|[^"\\])*"(?=\s*:)/], ["chaine", /"(?:\\.|[^"\\])*"?/], ["special", /\b(?:true|false|null)\b/], ["nombre", /-?\b\d+(?:\.\d+)?(?:e[+-]?\d+)?\b/]];
    case "html": return [
      ["com", /<!--[\s\S]*?(?:-->|$)/], ["balise", /<\/?[A-Za-z][\w:-]*|\/?>/], ["attr", /\b[\w:-]+(?==)/], ["chaine", /"[^"]*"?|'[^']*'?/], ["entite", /&[#\w]+;/]];
    case "css": return [
      ["com", /\/\*[\s\S]*?(?:\*\/|$)/], ["chaine", /"[^"\n]*"?|'[^'\n]*'?/], ["couleur", /#[\da-fA-F]{3,8}\b/],
      ["attr", /[\w-]+(?=\s*:)/], ["nombre", /-?\b\d+(?:\.\d+)?(?:px|em|rem|%|vh|vw|s|ms|deg|fr)?\b/], ["balise", /[.#]?[A-Za-z][\w-]*(?=[^{}]*\{)/], ["mot", /@[\w-]+|!important/]];
    case "bash": return [
      ["com", /#[^\n]*/], ["chaine", /"(?:\\.|[^"\\])*"?|'[^']*'?/], ["variable", /\$\{?[\w@#?*]+\}?/],
      ["mot", k(MOTS.bash)], ["fonction", /(?:^|(?<=[|;&]\s*))[\w./-]+/m], ["option", /\s--?[\w-]+/]];
    case "rust": case "go": case "c": case "php": case "lua": return [
      ["com", lang === "lua" ? /--\[\[[\s\S]*?(?:\]\]|$)|--[^\n]*/ : /\/\/[^\n]*|\/\*[\s\S]*?(?:\*\/|$)|#(?:include|define|if|ifdef|ifndef|endif|pragma)[^\n]*/],
      ["chaine", /r?#?"(?:\\.|[^"\\])*"?#?|`[^`]*`?|'(?:\\.|[^'\\\n]){0,4}'/],
      ["variable", lang === "php" ? /\$[A-Za-z_]\w*/ : /(?!)/], ["deco", /#!?\[[^\]\n]*\]|@[A-Za-z_]\w*/],
      ["mot", new RegExp(`\\b(?:${MOTS[lang]})\\b`)], ["special", k(SPECIAUX.commun)],
      ["nombre", /\b(?:0x[\da-fA-F_]+|0b[01_]+|\d[\d_]*(?:\.\d+)?(?:e[+-]?\d+)?[a-zA-Z0-9]*)\b/], ["constante", /\b[A-Z][A-Z0-9_]{2,}\b/],
      ["fonction", /\b[A-Za-z_]\w*!?(?=\s*\()/], ["classe", /\b[A-Z][A-Za-z0-9_]+\b/], ["propriete", /(?<=\.|->|::)[A-Za-z_]\w*/],
      ["op", /->|=>|::|==|!=|<=|>=|&&|\|\||[+\-*/%=<>!&|^~?:]/], ["par", /[()[\]{}]/]];
    case "ruby": return [
      ["com", /#[^\n]*/], ["chaine", /"(?:\\.|[^"\\])*"?|'(?:\\.|[^'\\])*'?/], ["variable", /@{1,2}[A-Za-z_]\w*|\$[A-Za-z_]\w*/], ["special", /:[A-Za-z_]\w*[?!]?/],
      ["mot", k(MOTS.ruby)], ["nombre", /\b\d[\d_]*(?:\.\d+)?\b/], ["fonction", /\b[a-z_]\w*[?!]?(?=\s*\()/], ["classe", /\b[A-Z]\w*/], ["op", /[+\-*/%=<>!&|^~]/], ["par", /[()[\]{}]/]];
    case "sql": return [
      ["com", /--[^\n]*|\/\*[\s\S]*?(?:\*\/|$)/], ["chaine", /'(?:''|[^'])*'?|"[^"]*"?/], ["mot", new RegExp(`\\b(?:${MOTS.sql}|${MOTS.sql.toUpperCase()})\\b`)],
      ["fonction", /\b[A-Za-z_]\w*(?=\s*\()/], ["nombre", /\b\d+(?:\.\d+)?\b/], ["op", /[=<>!*+\-/%,;]/], ["par", /[()]/]];
    case "yaml": return [
      ["com", /#[^\n]*/], ["cle", /^[ \t-]*[\w.\-"']+(?=\s*:(?:\s|$))/m], ["chaine", /"(?:\\.|[^"\\])*"?|'[^']*'?/],
      ["special", /\b(?:true|false|null|yes|no|on|off)\b/], ["nombre", /\b\d+(?:\.\d+)?\b/], ["variable", /[&*][\w-]+|\$\{\{?[^}\n]*\}?\}/], ["op", /^\s*-(?=\s)|[|>]-?$/m]];
    case "ini": return [
      ["com", /^\s*[#;][^\n]*/m], ["titre", /^\s*\[[^\]\n]+\]/m], ["cle", /^\s*[\w.\-]+(?=\s*=)/m], ["chaine", /"(?:\\.|[^"\\])*"?|'[^']*'?/],
      ["special", /\b(?:true|false|yes|no|on|off)\b/i], ["nombre", /\b\d+(?:\.\d+)?\b/], ["variable", /\$\{?\w+\}?/], ["op", /=/]];
    case "diff": return [["titre", /^(?:diff|index|@@)[^\n]*/m], ["ajout", /^\+[^\n]*/m], ["retrait", /^-[^\n]*/m]];
    case "docker": return [
      ["com", /#[^\n]*/], ["mot", new RegExp(`^\\s*(?:${MOTS.docker})\\b`)], ["chaine", /"(?:\\.|[^"\\])*"?|'[^']*'?/], ["variable", /\$\{?\w+\}?/], ["option", /\s--?[\w-]+/]];
    case "md": return [["titre", /^#{1,6} [^\n]*/m], ["chaine", /`[^`\n]+`/], ["mot", /\*\*[^*\n]+\*\*/], ["attr", /\[[^\]\n]+\]\([^)\n]+\)/], ["special", /^\s*(?:[-*+]|\d+\.)\s/m]];
    case "texte": return [];
    //  Un langage qu'on ne connaît pas : chaînes, commentaires, nombres et
    //  mots courants en couleurs plutôt que tout en blanc.
    default: return lang ? [
      ["com", /\/\/[^\n]*|\/\*[\s\S]*?(?:\*\/|$)|#[^\n]*|--[^\n]*/], ["chaine", /"(?:\\.|[^"\\\n])*"?|'(?:\\.|[^'\\\n])*'?/],
      ["mot", /\b(?:if|else|for|while|return|function|def|class|import|from|let|var|const|end|then|do|case|switch|break|continue|new|try|catch|public|private|static|void|module|use|fn|func)\b/],
      ["special", k(SPECIAUX.commun)], ["nombre", /\b\d+(?:\.\d+)?\b/], ["fonction", /\b[A-Za-z_]\w*(?=\s*\()/], ["op", /[+\-*/%=<>!&|^~?:]/], ["par", /[()[\]{}]/]] : [];
  }
}
const _cache = {};
function _regex(lang) {
  if (_cache[lang]) return _cache[lang];
  const r = _regles(lang);
  return (_cache[lang] = r.length ? { classes: r.map((x) => x[0]), re: new RegExp(r.map((x) => `(${x[1].source})`).join("|"), "gm") } : null);
}
const _esc = (s) => s.replace(/[&<>]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" }[c]));

/* Retourne le HTML coloré (déjà échappé) */
function colorier(code, langue) {
  const lang = LANGS[(langue || "").toLowerCase()] || (langue || "").toLowerCase();
  const R = code.length < 300000 && _regex(lang);
  if (!R) return _esc(code);
  let out = "", dernier = 0;
  R.re.lastIndex = 0;
  for (let m; (m = R.re.exec(code));) {
    if (!m[0]) { R.re.lastIndex++; continue; }
    const i = m.slice(1).findIndex((g) => g !== undefined);
    out += _esc(code.slice(dernier, m.index)) + `<span class="tk-${R.classes[i]}">${_esc(m[0])}</span>`;
    dernier = m.index + m[0].length;
  }
  return out + _esc(code.slice(dernier));
}
const langueDe = (chemin) => (chemin || "").split(".").pop().toLowerCase();
