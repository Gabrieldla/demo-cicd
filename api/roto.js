// Archivo con un error de estilo a propósito: variable declarada y nunca usada.
// ESLint lo marca con no-unused-vars y la etapa 1 se pone en rojo.
export function sumar(a, b) {
  const sinUsar = "esto no se usa en ninguna parte";
  return a + b;
}
