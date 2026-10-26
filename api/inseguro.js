// Vulnerabilidad metida a propósito para el B3: una ruta que ejecuta como código
// lo que llega en la URL. Es inyección de código de manual, y el SAST debe cazarla.
import express from "express";

export const rutasInseguras = express.Router();

rutasInseguras.get("/api/calcular", (req, res) => {
  // eslint-disable-next-line no-eval
  const resultado = eval(req.query.expresion);
  res.json({ resultado });
});
