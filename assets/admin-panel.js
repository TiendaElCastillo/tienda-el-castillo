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
 const status=String(card.dataset.orderStatus||"").toLowerCase();
 const provider=String(card.dataset.providerStatus||"").toLowerCase();
 const providerId=String(card.dataset.providerId||"");
 if(["completed","failed","rejected","cancelled"].includes(status))return "history";
 if(providerId||["created","confirmed","processing","partially_completed","completed","submitting","unknown"].includes(provider))return "provider";
 if(status==="processing")return "ready";
 if(["pending","payment_review"].includes(status))return "pending";
 const visible=(card.querySelector(".status")?.textContent||"").toLowerCase();
 if(visible.includes("complet")||visible.includes("fallid")||visible.includes("rechaz")||visible.includes("cancel"))return "history";
 if(card.querySelector("[data-provider-refresh]"))return "provider";
 if(card.querySelector("[data-provider-submit]"))return "ready";
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
 [["pending","Pendientes por confirmar"],["ready","Pago confirmado · listo"],["provider","En Central One"],["history","Finalizados"],["all","Todos"]].forEach(([key,label])=>{
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

function refreshCheckoutButton(){
 const button=document.getElementById("placeOrderBtn");if(!button)return;
 const productId=document.getElementById("product")?.value||"";
 const product=(typeof products!=="undefined"?products:[]).find(p=>String(p.id)===String(productId));
 const player=(document.getElementById("player")?.value||"").trim();
 const method=document.getElementById("payment")?.value||"";
 const proof=document.getElementById("paymentProof")?.files?.[0]||null;
 const reference=(document.getElementById("reference")?.value||"").trim();
 const senderPhone=(document.getElementById("senderPhone")?.value||"").trim();
 const senderDigits=senderPhone.replace(/\D/g,"");
 const reportedAmount=Number(document.getElementById("reportedAmount")?.value||0);
 const consent=document.getElementById("privacyConsent")?.checked===true;
 const verified=!product?.provider_product_id||(typeof validatedPlayerCheckout!=="undefined"&&validatedPlayerCheckout&&validatedPlayerCheckout.productId===String(product.id)&&validatedPlayerCheckout.playerId===player);
 const validFile=Boolean(proof)&&typeof validateProofFile==="function"&&!validateProofFile(proof);
 const needsReference=method==="Transferencia CUP";
 const needsSender=needsReference||method==="Saldo móvil";
 const needsReported=method==="Saldo móvil";
 const validReference=reference.length>=3&&reference.length<=100;
 const validSender=/^\+?[0-9\s().-]+$/.test(senderPhone)&&senderDigits.length>=8&&senderDigits.length<=15;
 const price=typeof priceForMethod==="function"&&product?Number(priceForMethod(product,method)):0;
 const validReported=Number.isFinite(reportedAmount)&&reportedAmount>0&&Math.abs(reportedAmount-price)<=0.01;
 const methodReady=typeof isPaymentMethodReady==="function"?isPaymentMethodReady(method):typeof paymentMethods!=="undefined"&&paymentMethods.some(item=>item.name===method&&item.active===true&&String(item.instructions||"").trim().length>0);
 const ready=Boolean(product&&player.length>=3&&player.length<=64&&verified&&methodReady&&validFile&&(!needsReference||validReference)&&(!needsSender||validSender)&&(!needsReported||validReported)&&consent&&price>0);
 button.disabled=!ready;
 button.textContent=ready?"Ya transferí · Enviar a revisión":!verified?"Primero verifica tu ID de jugador":!methodReady?"Este método de pago no está disponible":!validFile?"Adjunta la captura del comprobante":needsReference&&!validReference?"Escribe el N.º de transacción completo":needsSender&&!validSender?"Escribe el móvil desde el que pagaste":needsReported&&!validReported?"Confirma el importe exacto de saldo":!consent?"Acepta la política y los términos":"Completa los datos del pedido";
}
function installCheckoutFlow(){
 // La compra se dispara directamente desde cada tarjeta y su botón; no interceptamos el toque global.
 ["player","paymentProof","reference","senderPhone","reportedAmount","payment","privacyConsent"].forEach(id=>{
  const node=document.getElementById(id);if(!node||node.dataset.checkoutGate==="1")return;
  node.dataset.checkoutGate="1";
  node.addEventListener("input",refreshCheckoutButton);
  node.addEventListener("change",refreshCheckoutButton);
 });
 if(typeof window.openCheckout==="function"&&!window.openCheckout.__checkoutGateWrapped){
  const original=window.openCheckout;
  const wrapped=function(){const result=original.apply(this,arguments);refreshCheckoutButton();return result;};
  wrapped.__checkoutGateWrapped=true;window.openCheckout=wrapped;
 }
 if(typeof window.validatePlayerId==="function"&&!window.validatePlayerId.__checkoutGateWrapped){
  const original=window.validatePlayerId;
  const wrapped=async function(){const result=await original.apply(this,arguments);refreshCheckoutButton();return result;};
  wrapped.__checkoutGateWrapped=true;window.validatePlayerId=wrapped;
 }
 if(typeof window.resetPlayerValidation==="function"&&!window.resetPlayerValidation.__checkoutGateWrapped){
  const original=window.resetPlayerValidation;
  const wrapped=function(){const result=original.apply(this,arguments);refreshCheckoutButton();return result;};
  wrapped.__checkoutGateWrapped=true;window.resetPlayerValidation=wrapped;
 }
 if(typeof window.previewPaymentProof==="function"&&!window.previewPaymentProof.__checkoutGateWrapped){
  const original=window.previewPaymentProof;
  const wrapped=function(){const result=original.apply(this,arguments);refreshCheckoutButton();return result;};
  wrapped.__checkoutGateWrapped=true;window.previewPaymentProof=wrapped;
 }
}

function start(){initAdminLayout();installCheckoutFlow();installOrderRefreshFilter();installViewHook();if(document.getElementById("allorders"))applyOrderFilter(activeOrderFilter);}
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",start);else start();
window.updateCheckoutSubmitState=refreshCheckoutButton;
window.showAdminSection=showAdminSection;
window.applyAdminOrderFilter=applyOrderFilter;
})();