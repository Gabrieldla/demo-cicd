// Libro de visitas: cliente de la API del LAB-02.
//
// La API vive en /api/ del MISMO origen que la página: nginx reenvía esa ruta al backend.
// Por eso aquí no hay ninguna URL absoluta ni ningún puerto: eso es configuración de
// infraestructura, no del frontend.
const API = "/api";

const seccion = document.getElementById("libro-de-visitas");
const lista = document.getElementById("lista-mensajes");
const form = document.getElementById("form-mensaje");
const estado = document.getElementById("form-estado");

function pintar(mensajes) {
  lista.replaceChildren(
    ...mensajes.map((m) => {
      const li = document.createElement("li");
      const autor = document.createElement("strong");
      const texto = document.createElement("p");
      const fecha = document.createElement("time");
      // textContent, NUNCA innerHTML: lo que escribe un visitante es texto, no HTML.
      autor.textContent = m.nombre;
      texto.textContent = m.mensaje;
      fecha.textContent = new Date(m.fecha).toLocaleString("es-PE");
      li.append(autor, fecha, texto);
      return li;
    })
  );
}

async function cargar() {
  const r = await fetch(`${API}/mensajes`, { headers: { Accept: "application/json" } });
  // En GitHub Pages /api/mensajes devuelve un 404 con HTML: eso NO es la API.
  const esJson = (r.headers.get("content-type") || "").includes("application/json");
  if (!r.ok || !esJson) throw new Error(`la API no está disponible (HTTP ${r.status})`);
  pintar(await r.json());
}

form.addEventListener("submit", async (e) => {
  e.preventDefault();
  const datos = Object.fromEntries(new FormData(form));
  estado.textContent = "Enviando…";
  try {
    const r = await fetch(`${API}/mensajes`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(datos),
    });
    const cuerpo = await r.json();
    if (!r.ok) throw new Error(cuerpo.error || `HTTP ${r.status}`);
    form.reset();
    estado.textContent = "¡Gracias por tu mensaje!";
    await cargar();
    await mostrarTotal();
  } catch (err) {
    estado.textContent = `No se pudo enviar: ${err.message}`;
  }
});

// El total sale de /api/estadisticas, no de contar la lista: la lista está limitada
// a 100 mensajes, así que contarla daría un número equivocado en cuanto haya más.
async function mostrarTotal() {
  const el = document.getElementById("total-mensajes");
  if (!el) return;
  try {
    const r = await fetch(`${API}/estadisticas`, { headers: { Accept: "application/json" } });
    if (!r.ok) return;
    const { total } = await r.json();
    el.textContent = total === 1 ? "(1 mensaje)" : `(${total} mensajes)`;
  } catch {
    // Si falla, la sección se queda sin el contador y el resto sigue funcionando.
  }
}

// Degradación elegante: la sección solo aparece si el backend contesta.
cargar()
  .then(mostrarTotal)
  .then(() => { seccion.hidden = false; })
  .catch((err) => console.info("Libro de visitas oculto:", err.message));
