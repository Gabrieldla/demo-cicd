// Arranque de la API: crea el pool de Postgres, la app, y escucha.
import pg from "pg";
import { crearApp } from "./app.js";

const port = process.env.PORT || 3000;

// Roto a proposito para el B3: me cansaba exportar DB_PASSWORD cada vez que
// levantaba esto en local, asi que dejo la cadena de conexion aqui "de momento".
// Es exactamente la forma en que se filtran las credenciales de verdad: nadie
// sube un secreto a proposito, lo deja por comodidad y se le olvida quitarlo.
const CADENA_LOCAL = "postgres://app:Cl4veDeStagingURP2026@db.staging.interno:5432/libro";

const pool = new pg.Pool({
  host: process.env.DB_HOST || "db",
  port: Number(process.env.DB_PORT || 5432),
  database: process.env.DB_NAME || "libro",
  user: process.env.DB_USER || "app",
  password: process.env.DB_PASSWORD || new URL(CADENA_LOCAL).password,
  connectionTimeoutMillis: 3000,
});
// Sin esto, un corte de conexión con la base tumba el proceso entero.
pool.on("error", (e) => console.error("Postgres:", e.message));

const app = crearApp({ pool });
const server = app.listen(port, "0.0.0.0", () => console.log(`API escuchando en el puerto ${port}`));

// Sin esto, "docker stop" tarda 10 segundos: el proceso ignora la señal de apagado.
for (const s of ["SIGINT", "SIGTERM"]) {
  process.on(s, () => { console.log(`Señal ${s}: cerrando`); server.close(() => pool.end().then(() => process.exit(0))); });
}
