(function(){
"use strict";
let activeOrderFilter="pending";
const groupLabels={pending:"Pendientes de pago",ready:"Listos para autorizar",provider:"En Central One",history:"Finalizados",all:"Todos"};
function el(tag,cls,text){const n=document.createElement(tag);if(cls)n.className=cls;if(text!==undefined)n.textContent=text;return n;}
function initAdminLayout(){
 const admin=document.getElementById("admin");if(!admin||admin.dataset.organized==="1")return;
 const panels=Array.from(admin.children).filter(n=>n.classList&&n.classList.contains("panel"));
 if(panels.length!==6)return;
 admin.dataset.organized="1";
 const heading=el("div","admin-heading");
 heading.append(el("div","admin-kicker","PANEL DE CONTROL"));
 heading.append(el("h1","","Administración"));
 heading.append(el("p","subtle","Cada herramienta en su apartado. Entra solo en lo que necesitas."));
 const nav=el("nav","admin-tabs");nav.setAttribute("aria-label","Apartados de administración");
 const tabs=[["overview","Resumen"],["orders","Pedidos"],["products","Productos"],["payments","Pagos"],["pricing","Precios y capital"],["central","Central One"]];
 tabs.forEach(([key,label])=>{const b=el("button","admin-tab"+(key==="overview"?" active":""),label);b.type="button";b.dataset.adminTab=key;b.addEventListener("click",()=>showAdminSection(key));nav.append(b);});
 const overview=el("div","panel admin-overview");overview.dataset.adminSection="overview";
 overview.append(el("h2","","Tu negocio, organizado"));
 overview.append(el("p","subtle","Entra en cada apartado para administrar una sola parte del negocio."));
 const shortcuts=el("div","admin-shortcuts");
 const cards=[["orders","Pedidos","Revisa pagos y autoriza recargas"],["products","Productos","Crea, edita y activa paquetes"],["payments","Pagos","Configura cobros y revisa depósitos"],["pricing","Precios y capital","Actualiza tasas y calcula precios"],["central","Central One","Consulta catálogo y saldo mayorista"]];
 cards.forEach(([key,title,desc])=>{const b=el("button","admin-shortcut");b.type="button";b.append(el("strong","",title),el("span","",desc));b.addEventListener("click",()=>showAdminSection(key));shortcuts.append(b);});
 overview.append(shortcuts,el("p","track-note","Importante: primero confirma el pago del cliente. Después, en «Pedidos», autoriza la recarga real para que Central One utilice tu saldo."));
 const sectionForPanel=["central","central","pricing","products","payments","orders"];
 panels.forEach((panel,i)=>{panel.dataset.adminSection=sectionForPanel[i];panel.classList.add("admin-section-panel");});
 admin.insertBefore(overview,panels[0]);
 admin.insertBefore(nav,overview);
 admin.insertBefore(heading,nav);
 setupOrderFilters(panels[5]);
 showAdminSection("overview");
}
function showAdminSection(key){
 const valid=["overview","orders","products","payments","pricing","central"];
 const selected=valid.includes(key)?key:"overview";
 document.querySelectorAll("#admin [data-admin-section]").forEach(n=>n.classList.toggle("hidden",n.dataset.adminSection!==selected));
 document.querySelectorAll("#admin [data-admin-tab]").forEach(n=>n.classList.toggle("active",n.dataset.adminTab===selected));
}
function classifyOrder(card){
 if(card.querySelector("[data-provider-submit]"))return "ready";
 if(card.querySelector("[data-provider-refresh]"))return "provider";
 const status=(card.querySelector(".status")?.textContent||"").toLowerCase();
 if(status.includes("completada")||status.includes("fallida")||status.includes("rechazado")||status.includes("cancelado"))return "history";
 if(status.includes("pendiente")||status.includes("verificando"))return "pending";
 if(status.includes("pago confirmado"))return "ready";
 return "pending";
}
function applyOrderFilter(group){
 activeOrderFilter=groupLabels[group]?group:"pending";
 const container=document.getElementById("allorders");if(!container)return;
 const cards=Array.from(container.querySelectorAll(":scope > .order-card"));
 let visible=0;const counts={pending:0,ready:0,provider:0,history:0,all:cards.length};
 cards.forEach(card=>{const category=classifyOrder(card);counts[category]++;const show=activeOrderFilter==="all"||category===activeOrderFilter;card.classList.toggle("hidden",!show);if(show)visible++;});
 document.querySelectorAll("[data-order-filter]").forEach(b=>{b.classList.toggle("active",b.dataset.orderFilter===activeOrderFilter);const badge=b.querySelector(".admin-filter-count");if(badge)badge.textContent=String(counts[b.dataset.orderFilter]||0);});
 const empty=document.getElementById("adminOrderFilterEmpty");if(empty){empty.classList.toggle("show",cards.length>0&&visible===0);empty.textContent="No hay pedidos en este apartado.";}
}
function setupOrderFilters(panel){
 const container=panel.querySelector("#allorders");if(!container)return;
 const intro=el("p","track-note","Los pedidos están separados por etapa. En «Listos para autorizar» encontrarás el botón que envía la recarga a Central One.");
 const filters=el("div","admin-order-filters");filters.setAttribute("aria-label","Filtrar pedidos");
 [["pending","Pendientes de pago"],["ready","Listos para autorizar"],["provider","En Central One"],["history","Finalizados"],["all","Todos"]].forEach(([key,label])=>{
  const b=el("button","admin-order-filter"+(key==="pending"?" active":""));b.type="button";b.dataset.orderFilter=key;b.append(document.createTextNode(label+" "));b.append(el("span","admin-filter-count","0"));b.addEventListener("click",()=>applyOrderFilter(key));filters.append(b);
 });
 const empty=el("div","admin-filter-empty","No hay pedidos en este apartado.");empty.id="adminOrderFilterEmpty";
 container.parentNode.insertBefore(intro,container);container.parentNode.insertBefore(filters,container);container.parentNode.insertBefore(empty,container.nextSibling);
}
function installOrderRefreshFilter(){
 if(typeof window.loadAllOrders!=="function"||window.loadAllOrders.__castleWrapped)return;
 const original=window.loadAllOrders;
 const wrapped=async function(){const result=await original.apply(this,arguments);applyOrderFilter(activeOrderFilter);return result;};
 wrapped.__castleWrapped=true;window.loadAllOrders=wrapped;
}
function installViewHook(){
 if(typeof window.showView!=="function"||window.showView.__castleWrapped)return;
 const original=window.showView;
 const wrapped=function(name){const result=original.apply(this,arguments);if(name==="admin")showAdminSection("overview");return result;};
 wrapped.__castleWrapped=true;window.showView=wrapped;
}
function start(){initAdminLayout();installOrderRefreshFilter();installViewHook();if(document.getElementById("allorders"))applyOrderFilter(activeOrderFilter);}
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",start);else start();
window.showAdminSection=showAdminSection;
window.applyAdminOrderFilter=applyOrderFilter;
})();