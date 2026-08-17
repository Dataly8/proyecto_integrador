# Análisis de churn y sistema de alerta temprana — RavenStack

*Churn analysis and early-warning system for a SaaS company. Documentation in Spanish.*

Análisis completo del abandono de clientes de una empresa SaaS de suscripción: desde la extracción de datos hasta un sistema de retención priorizado y un dashboard operativo. El proyecto identifica qué comportamientos anticipan una cancelación, cuantifica su coste y devuelve una lista de cuentas sobre la que un equipo puede actuar.

**Stack:** Python · MySQL · Power BI

> **Sobre los datos.** RavenStack es una empresa ficticia. El diagnóstico se realiza sobre un conjunto de datos sintético construido para este proyecto, con el esquema y los volúmenes del dataset original de Kaggle. Los hallazgos ilustran lo que el procedimiento es capaz de detectar; no describen el comportamiento de clientes reales.

---
[Ver la memoria](https://drive.google.com/file/d/13HepIFs_j4UyYcAgmvKH8feQD0hRpxZq/view)

## Dashboard 

![Cartera en riesgo](<img width="1312" height="731" alt="Captura de pantalla 2026-08-15 100539" src="https://github.com/user-attachments/assets/08876be3-721d-46b7-842b-678451300eb2" />)

**[Ver el dashboard completo →](https://app.powerbi.com/view?r=eyJrIjoiNmQ5N2IwMDYtMTFjNS00YWYxLWEwNDktN2MzNDhhMjZkMTdlIiwidCI6IjM1MWZmYjE3LTRkZWItNGUyNi1iY2I1LTAyYjZjMjM2MTAwNCIsImMiOjh9&embedImagePlaceholder=true&pageName=4ce12d7f1ea7e18068a2)**

Cuatro páginas, una pregunta por página: situación del negocio, diagnóstico del abandono, cartera en riesgo y plan de acción.

---

## Las preguntas de negocio

| | Pregunta | Respuesta |
|---|---|---|
| 1 | ¿Cuánto churn hay y cuánto cuesta? | 23,8 % de las cuentas · 6,2 M de facturación anual |
| 2 | ¿Se van los clientes pequeños o los grandes? | Ninguno: el tamaño no discrimina |
| 3 | ¿Por qué se van y qué motivo cuesta más? | Producto y soporte concentran el 68 % de las bajas |
| 4 | ¿Qué señal anticipa la cancelación? | La degradación del uso y la fricción de soporte |

---

## Hallazgos principales

**El coste real no está en los reembolsos.** Las devoluciones abonadas a los clientes que se marcharon suman 1.934 $. La facturación que esas cuentas ya no generarán asciende a 6,2 M.

**No es quién es el cliente, es lo que le pasa.** El plan contratado, el sector y el tamaño de la cuenta arrojan tasas de cancelación entre el 18,7 % y el 28,3 %, todas alrededor de la media. Lo que sí distingue a las cuentas que se marchan es su experiencia con el producto:

| Trimestre previo a la baja | Activas | Perdidas |
|---|---|---|
| Acciones por sesión de uso | 10,35 | **4,59** |
| Sesiones en el trimestre | 30,0 | **18,2** |
| Errores técnicos por sesión | 0,475 | **0,805** |
| Satisfacción con soporte (1-5) | 3,55 | **2,86** |
| Incidencias escaladas | 7,2 % | **16,4 %** |

**El deterioro es gradual, no abrupto.** La desconexión total es igual de infrecuente entre las cuentas que se marchan y las que permanecen (1,7 % frente a 1,8 %). Nadie deja de usar el producto y después cancela: reduce su actividad progresivamente. Esperar al silencio para intervenir supone llegar tarde.

**El riesgo es uniforme, el daño no.** El 30 % de cuentas de mayor facturación concentra el 64 % de los ingresos. Once bajas del decil superior cuestan casi cuatro veces más que cuarenta y dos del inferior.

---

## El sistema de alerta temprana

Una tarjeta de puntos en SQL que combina seis señales observables, cruza el riesgo resultante con el valor expuesto de cada cuenta y devuelve una lista priorizada:

| Acción | Cuentas | Facturación expuesta |
|---|---|---|
| Intervención directa | 13 | 1,68 M |
| Contacto proactivo | 54 | 5,08 M |
| Campaña automatizada | 62 | 2,22 M |

**Validación.** Situándose en junio de 2024 y puntuando la cartera con información exclusivamente anterior a esa fecha, las cuentas señaladas como riesgo alto abandonaron cinco veces más que las de riesgo bajo en los seis meses siguientes.

Se completa con un recomendador de funcionalidades basado en la brecha de adopción entre cuentas sanas y cuentas en riesgo.

---

## Decisiones técnicas

**Tarjeta de puntos frente a modelo entrenado.** El sistema no ejecuta acciones automáticas: produce una lista que un equipo humano debe atender. Un modelo que devuelve una probabilidad sin explicación no llega a usarse. La interpretabilidad era un requisito del caso de uso.

**Corte temporal estricto.** Cada cuenta se evalúa desde su propia fecha de referencia —la de baja para las que se marcharon, el cierre del periodo para las activas— y solo con información anterior a ella. Sin esa restricción, las métricas de recencia describirían la consecuencia del abandono en lugar de anticiparlo.

**Contraste de las diferencias.** Cada diferencia entre grupos se comparó con su margen de error. Dos de las señales de soporte no lo superaron y se reportaron como tendencia, no como hallazgo.

**Corrección de un artefacto en el recomendador.** Las 40 funcionalidades mostraban brecha favorable a las cuentas sanas, simplemente porque estas exploran más el producto (16,6 frente a 10,7 funcionalidades de media). Solo 15 superan la brecha que la amplitud explica por sí sola; el recomendador descarta el resto.

---

## Estructura del repositorio

```
├── 01_python/
│   └── ravenstack_extraccion_eda_ingesta.ipynb   Extracción vía API, EDA e ingesta
├── 02_sql/
│   ├── 01_ddl_ravenstack_gemelo.sql              Modelo relacional y restricciones
│   ├── 02_analisis_ravenstack_gemelo.sql         Diagnóstico y sistema de alerta
│   └── 03_vistas_powerbi.sql                     Vistas que consume el dashboard
├── 03_datos/
│   ├── *.csv                                     Las cinco tablas
│   └── NOTA_TECNICA_GEMELO.md                    Cómo se construyó el conjunto
└── 04_documentacion/
    ├── Informe_Proyecto_Integrador.pdf           Memoria completa
    └── Brief_Comite_RavenStack.pdf               Informe ejecutivo
```

---

## Cómo reproducirlo

**Requisitos:** Python 3.10+, MySQL 8.0, Power BI Desktop.

```bash
pip install pandas sqlalchemy pymysql python-dotenv kagglehub
```

**1. Credenciales.** Copiar `.env.example` como `.env` y rellenarlo:

```
DB_USER=tu_usuario
DB_PASSWORD="tu_contraseña"
DB_HOST=localhost
DB_PORT=3306
DB_NAME_GEMELO=ravenstack_gemelo
RUTA_DATOS_GEMELO=/ruta/a/03_datos
```

El archivo `.env` no se incluye en el repositorio por contener credenciales.

**2. Base de datos.** Ejecutar `02_sql/01_ddl_ravenstack_gemelo.sql` en MySQL Workbench.

**3. Ingesta.** Ejecutar el notebook de `01_python/`. El bloque de extracción descarga el dataset original desde Kaggle para reproducir el análisis exploratorio; el de ingesta carga los CSV de `03_datos/`.

**4. Análisis.** Ejecutar `02_sql/02_analisis_ravenstack_gemelo.sql` y después `03_vistas_powerbi.sql`.

**5. Dashboard.** Conectar Power BI a la base `ravenstack_gemelo` en modo importación.

---

## Sobre el alcance de este repositorio

El análisis exploratorio del notebook corresponde al **dataset original de RavenStack**. Ese conjunto resultó no admitir un diagnóstico de churn: presentaba dos fuentes de abandono contradictorias y una incoherencia temporal que impedía construir cualquier métrica de anticipación. La memoria documenta esa auditoría en la Fase 3 y explica en la Fase 4 cómo se construyó el conjunto sintético sobre el que se realiza el diagnóstico, incluida la validación de que el procedimiento analítico detecta señal cuando existe.

Los scripts de auditoría y de generación del conjunto sintético no se incluyen en este repositorio; su contenido está documentado en la memoria y están disponibles bajo petición.

---

## Créditos

**Dataset original:** River @ Rivalytics — *RavenStack: Synthetic SaaS Dataset (Multi-Table)*, publicado en Kaggle bajo licencia MIT-like. Datos totalmente sintéticos, sin información personal.

**Herramientas de IA:** el desarrollo contó con el apoyo de Claude (Anthropic) para la generación del conjunto sintético, la revisión de código SQL, la orientación metodológica y el apoyo en redacción. Las decisiones analíticas y la interpretación de los resultados corresponden a la autora. La memoria detalla el alcance de ese uso.

---

**Marta Quevedo Oltra** · Proyecto Integrador · Unicorn Academy
