// Patrón peligroso a propósito: ejecutar como código una cadena que viene del
// usuario. Semgrep lo detecta y la etapa 2 (SAST) se pone en rojo.
export function calcular(expresionDelUsuario) {
  // eslint-disable-next-line no-eval
  return eval(expresionDelUsuario);
}
