#!/usr/bin/env node
// Banc UI du menu animé, sans navigateur ni serveur : tester le code réellement livré.
"use strict";
const fs = require("fs");
const vm = require("vm");
const path = require("path");
const assert = require("node:assert/strict");

const root = path.resolve(__dirname, "..");
const script = fs.readFileSync(
  path.join(root, "config/includes.chroot/usr/share/lexos/volet/web/app.js"), "utf8");
const css = fs.readFileSync(
  path.join(root, "config/includes.chroot/usr/share/lexos/volet/web/style.css"), "utf8");
const start = script.indexOf("let effetsOuvert = false;");
const end = script.indexOf("function rapidesHTML(){", start);
assert(start >= 0 && end > start, "bloc d'animations manquant dans app.js");
const source = script.slice(start, end) +
  "\nglobalThis.test = { effetsHTML, effetsOuvre, effetsFerme, effetsChoisit };\n";
let render = 0;
let refresh = 0;
const calls = [];
const ctx = {
  etat: {rapides:{effet:"crt",crt:true}},
  photoOuvert: false,
  esc: value => String(value).replace(/[&<>"]/g, c=>({
    "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c])),
  rend:()=>{render++;},
  rafraichir: async()=>{refresh++;},
  api:async(action, profile)=>{
    calls.push([action,profile]);
    if(profile==="neon"){
      ctx.etat.rapides.effet="neon";
      return {ok:true};
    }
    return {ok:false, erreur:"Picom est encore occupé"};
  },
  Object, console
};
vm.createContext(ctx);
vm.runInContext(source,ctx);
let html = ctx.test.effetsHTML();
for(const n of ["Vieille télévision","Fluide","Hologramme","Néon orange",
                 "Portail","Sans animation"]){
  assert(html.includes(n), "option manquante : "+n);
}
assert(html.includes('aria-pressed="true"'));
assert(html.includes("retour"));
ctx.test.effetsOuvre();
assert(render > 0);
assert.equal(ctx.photoOuvert,false);
(async()=>{
  await ctx.test.effetsChoisit("neon");
  assert.equal(calls[0][0],"rapides-effet");
  assert.equal(calls[0][1],"neon");
  assert.equal(refresh,1);
  assert(ctx.test.effetsHTML().includes("✓"));
  await ctx.test.effetsChoisit("crt");
  assert.equal(calls.length,2);
  assert(ctx.test.effetsHTML().includes("Picom est encore occupé"));
  await ctx.test.effetsChoisit("../../etc/passwd");
  assert.equal(calls.length,2,"profil non prévu transmis au backend");
  ctx.test.effetsFerme();
  assert(css.includes(".qs-effets-bt.actif"));
  assert(css.includes(".qs-effets-choix"));
  console.log("✓ Panneau Animations : six choix, clics contrôlés, erreur et retour : OK");
})().catch(err=>{console.error(err);process.exitCode=1;});
