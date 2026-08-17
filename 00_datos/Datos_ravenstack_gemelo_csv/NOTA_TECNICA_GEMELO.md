# Nota técnica — Gemelo sintético de RavenStack

Documento de trabajo. Es la base de la que sale la sección de metodología de la
memoria, **no** un texto para copiar tal cual.

---

## 1. Qué es y qué no es

**Es** un banco de pruebas con verdad de terreno conocida, generado a partir del
esquema de RavenStack, para responder a una pregunta metodológica concreta:

> El diagnóstico sobre RavenStack no encuentra señal. ¿No hay señal, o el método
> es ciego?

**No es** una versión mejorada de RavenStack, ni una fuente de conclusiones sobre
el negocio. Cualquier relación que el análisis encuentre en el gemelo fue
inyectada deliberadamente en el generador. Recuperarla no es un hallazgo.

La frase defendible es: *«en un entorno controlado donde inyecté X, el pipeline
lo recuperó, luego el pipeline tiene sensibilidad demostrada»*. La frase que
nunca debe aparecer es: *«el churn de RavenStack se explica por X»*.

---

## 2. Estructura causal inyectada

Existe una variable latente **no observable en ninguna tabla**: la salud de la
cuenta. Causa a la vez el comportamiento observable y el churn.

```
salud (latente, no está en ninguna tabla)
  ├──> amplitud de adopción de features
  ├──> intensidad de uso y su degradación previa a la baja
  ├──> errores técnicos
  ├──> fricción de soporte (volumen, tiempos, escalados, satisfacción)
  ├──> contexto comercial (auto-renovación, downgrades)
  └──> probabilidad de churn
```

El análisis no descubre la salud. Descubre sus **proxies observables**. Esa es la
diferencia entre analizar y recuperar los parámetros del generador.

### Variables de control (sin efecto, a propósito)

`country`, `industry` y `plan_tier` **no** influyen en el churn. Están ahí para
que el análisis tenga que discriminar señal de ruido. Un dataset donde todo
predice el churn es tan poco creíble como uno donde nada lo hace.

`referral_source` sí tiene efecto (organic 42% de churn → ads 81%). Salió más
fuerte de lo previsto: quedó como señal de primer orden, no como señal débil.

---

## 3. Las tres variantes

| Carpeta | `--signal` | Para qué sirve |
|---|---|---|
| `gemelo_nulo` | 0.0 | Control. Réplica **sin** señal. Debe reproducir la planitud de RavenStack |
| `gemelo_debil` | 0.5 | Umbral de detección |
| `gemelo_fuerte` | 1.0 | Escenario principal del proyecto |

Cada carpeta incluye `_ground_truth.csv` con la salud latente y el churn real.
**No forma parte del dataset**: es solo para medir precisión y cobertura. No debe
ingestarse en MySQL ni aparecer en Power BI.

---

## 4. Qué se conserva del original (verificado)

Volúmenes: `accounts` 500, `feature_usage` 25.000 y `support_tickets` 2.000 se
conservan exactos. `subscriptions` y `churn_events` **no**: ver sección 5.

Nombres, orden y tipos de columna idénticos. Integridad referencial completa,
cero huérfanos. Todos los valores dentro de los límites del DDL.

**La tabla `accounts` es idéntica al original** salvo `churn_flag`. Eso significa
que todo el EDA de esa tabla sigue siendo literalmente cierto: media de seats
20,6, mediana 15, máximo 163, US dominante, Pro el plan más contratado.

Defectos documentados que se conservan a propósito, para que el trabajo de
limpieza de las fases 1 y 2 siga siendo aplicable:

- 21 `usage_id` duplicados (42 filas)
- 33 suscripciones sin ningún uso registrado
- `end_date` nulos legítimos en suscripciones activas
- nulos en `satisfaction_score` y `feedback_text`
- desincronización de `seats` entre `accounts` y `subscriptions`
- **la contradicción entre `churn_flag` y `churn_events`**: 110 True en
  `accounts`, de los cuales solo 75 coinciden con `churn_events`; 35 flags sin
  evento y 277 eventos sin flag. Es lo que justifica elegir una única fuente de
  verdad, y era un hallazgo demasiado bueno para perderlo.

---

## 5. Lo que sí cambia (y hay que documentar)

| # | Cambio | Por qué |
|---|---|---|
| 1 | Las suscripciones de cuentas dadas de baja se cierran alrededor de su fecha de churn | En el original `churn_events` y `subscriptions` estaban desconectadas y el revenue churn era incalculable |
| 2 | `satisfaction_score` baja de 3 (ahora 1–5) | Sin varianza por debajo de 3 el soporte no puede ser un proxy de nada |
| 3 | Tasa de escalado sube del 4,75% a ~8% | Necesita rango para discriminar |
| 4 | `reason_code` deja de ser plano | Ahora se correlaciona con los drivers, de modo que la consulta de causas tiene respuesta |
| 5 | `feedback_text` coherente con `reason_code` | En el original iban desacoplados |
| 6 | Ninguna reactivación es el primer evento de una cuenta | Corrige las 26 secuencias incoherentes que quedaron aparcadas |
| 7 | **Tasa de churn del 60% al 23,8%** (119 cuentas) | El 60-70% acumulado no es creíble en un SaaS. Decisión tomada explícitamente |
| 8 | **`subscriptions` de 5.000 a ~1.164 filas** (media 2,33 por cuenta, no 10) | Las 10 fijas del original inflaban el ARR a cifras absurdas |
| 9 | **`churn_events` de 600 a 238 filas** | Se deriva del número de cuentas dadas de baja, manteniendo la proporción de 1,7 eventos por cuenta |

Los cambios 7, 8 y 9 son los que más documentación tocan: **todo el EDA de
`subscriptions` y de `churn_events` hay que rehacerlo**. El de `accounts`,
`feature_usage` y `support_tickets` se mantiene.

Se conservan deliberadamente dos límites documentados en el EDA: resolución
máxima 72 h y primera respuesta máxima 180 min.

---

## 6. Resultados de la validación end-to-end

Ejecutado sobre MariaDB 10.11 con el DDL sin modificar y las consultas de la
Fase 3 sin modificar.

Churn real: **119 cuentas, 23,8%**.

### Señal detectada al nivel de la vista `estado_churn_cuenta`

| Métrica | Se queda | Se va |
|---|---|---|
| Amplitud de features | 13,82 | 9,13 |
| Tickets por cuenta | 3,80 | 5,62 |
| Horas de resolución | 32,4 | 39,6 |
| Satisfacción | 3,45 | 2,80 |
| Tasa de escalado | 9,5% | 17,7% |
| ARR medio | 60.909 | 33.225 |

Controles planos: `plan_tier` 20,2–28,1%; `country` (US, el único grupo grande)
24,1% frente a una base del 23,8%.

Canal de captación (señal deliberada, salió fuerte): organic 10,5% → ads 41,8%.

Revenue churn, ahora calculable: 5,87 M de ARR perdido frente a 24,37 M vivo.
ARR por cuenta: mediana 44.964.

### Curva de sensibilidad del recomendador

Tres semillas × dos fechas de corte, validación temporal (corte + horizonte de
180 días), solo cuentas vivas en el corte:

| Señal inyectada | Lift medio | Desviación | Cuentas evaluables |
|---|---|---|---|
| 0.0 (control) | **0,99** | 0,32 | 230 |
| 0.5 (débil) | **2,09** | 0,28 | 234 |
| 1.0 (fuerte) | **2,42** | 0,61 | 238 |

Tasa base de baja en la ventana de resultado: ~15%.

Lectura: el método **no detecta nada** cuando no hay nada (0,84 ≈ azar), y sí
detecta cuando hay algo. Eso es lo que convierte el nulo de RavenStack en un
verdadero negativo y no en una ceguera del método.

---

## 7. Limitaciones honestas

1. **El método satura.** Entre señal 0,5 y señal 1,0 el lift apenas se mueve
   (1,38 → 1,55, dentro de una desviación). La tarjeta de puntos detecta
   *presencia* de señal, no *magnitud*. Es una limitación real del scorecard por
   terciles y hay que decirlo en la memoria.

2. **Lift de 2,42 está en rango de producción.** Un sistema de alerta temprana
   real aspira a 2–3×. Con la desviación de 0,61 hay que reportarlo como
   "entre 1,8 y 3,0", no como un número seco.

3. **La población evaluable es de ~238 cuentas** de 500 en cualquier corte.

4. **La densidad de uso es baja.** 25.000 eventos entre 500 cuentas son ~50
   eventos por cuenta en dos años. Una ventana de 90 días contiene muy pocos
   eventos, así que las métricas de tendencia son ruidosas. Se conservó ese
   volumen para no romper el EDA; subirlo mejoraría el trigger.

5. **El efecto del canal de captación salió muy fuerte** (organic 10,5% → ads
   41,8%, un factor de 4). Es plausible en un SaaS real, pero convierte a
   `referral_source` en el predictor más obvio del dataset. Si parece demasiado
   limpio, se puede atenuar en `penal_referral`.

6. **Solo 119 casos positivos.** Cualquier corte por subgrupos se queda sin
   base muestral enseguida. Es el precio de una tasa de churn realista.

7. **Realismo estadístico limitado.** Los datos son plausibles, no
   indistinguibles de datos reales. Un revisor meticuloso encontrará estructuras
   de correlación más limpias de lo que serían en producción y ausencia del
   confounding real.

---

## 8. Dos errores de diseño que aparecieron al testear

Se documentan porque son buen material para la memoria: muestran que el banco de
pruebas se validó de verdad y no se dio por bueno.

**Error 1 — sesgo de supervivencia autoinducido.** La primera versión acoplaba la
salud a la *fecha* de baja: las cuentas sanas se iban más tarde. Consecuencia: las
cuentas vivas en cualquier fecha de corte eran una muestra sesgada hacia la buena
salud y la señal se evaporaba justo en la población que el recomendador debe
servir. El lift salía 0,9, peor que el azar. Corregido: la salud decide **si** se
va, no **cuándo**.

**Error 2 — ventana de degradación demasiado corta.** La degradación arrancaba 90
días antes de la baja, y se pedía al trigger anticipar a 180 días. Un sistema no
puede anticipar seis meses una señal que nace tres meses antes del evento.
Ventana ampliada a 210 días.

Y un tercero, este del lado del análisis: **la amplitud de features sin normalizar
mide antigüedad, no adopción.** Una cuenta más vieja acumula más features
distintas por el mero paso del tiempo. Sin normalizar entraba en la tarjeta con
el signo invertido y empeoraba el score. Normalizada por `sqrt(nº de eventos)`.

---

## 9. Fuga de información: el punto que hay que defender

En el gemelo conviven dos señales de naturaleza distinta, y no distinguirlas es
el error más caro que se puede cometer aquí.

**Recencia (contaminada).** Una cuenta que se fue en marzo no registra uso en
diciembre. Su recencia a 31-12 es de 300 días. Eso no predice el churn: es una
**consecuencia** de él. La vista `rfm_por_cuenta` la calcula así, y para
diagnosticar está bien. Para predecir, no vale.

**Degradación previa (legítima).** En los meses anteriores a la baja, la
intensidad y la frecuencia de uso caen respecto a la línea base de la propia
cuenta. Es observable **antes** del evento. Es lo único sobre lo que se puede
construir una alerta temprana.

Por eso `recomendador.py` corta el tiempo en dos: solo usa datos anteriores a la
fecha de corte y solo evalúa cuentas vivas en esa fecha. Un modelo que ignore
esto dará métricas espectaculares y no servirá para nada.

---

## 10. Uso

```bash
# generar variantes
python generar_gemelo.py --signal 1.0 --seed 42 --n-churn 140 --out ./gemelo_fuerte
python generar_gemelo.py --signal 0.0 --seed 42 --n-churn 140 --out ./gemelo_nulo

# evaluar el recomendador con validación temporal
python recomendador.py --datos gemelo_fuerte --corte 2024-06-30 --horizonte 180
```

Parámetros: `--n-churn` (cuentas con evento de churn, por defecto 140 → ~24% de
churn real), `--subs-media` (suscripciones por cuenta), `--seed`, `--signal`,
`--origen` (carpeta con los CSV de partida, de los que solo se lee `accounts`
y la lista de features).
