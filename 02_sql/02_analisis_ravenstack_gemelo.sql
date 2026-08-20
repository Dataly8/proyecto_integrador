/* 
=============================================================================================================================== 
Archivo Análisis | Proyecto Integrador RavenStack
Autora: Marta Quevedo Oltra | Unicorn Edition 13.0
Fase 5. Diagnóstico del churn 

NOTA: 
Este archivo es el diagnóstico oficial de análisis de churn (sobre el dataset ravenstack_gemelo). 
Todos los resultados de estas consultas quedan documentados e interpretados en la memoria del proyecto, consulta a consulta 
a partir del apartado Fase 5 (página 36).
=============================================================================================================================== 
 */

USE ravenstack_gemelo;


/* BLOQUE 0 · PUNTO DE PARTIDA */
                                                
-- Verificación 1.-- Los trials no contaminan las métricas de ingresos 
# OBJETIVO: fiarnos de la columna 'mrr_amount' como métrica de ingresos 
# y no mezclar subscripciones en período de prueba: mrr = 0 = ¿is trial?
SELECT
	COUNT(subscription_id) total_subscriptions,
    CASE
		WHEN mrr_amount = 0 AND is_trial = 1 THEN 'Hipótesis verificada'
        WHEN mrr_amount > 0 AND is_trial = 0 THEN 'Subscripción Normal'
        WHEN mrr_amount > 0 AND is_trial = 1 THEN 'Anomalía'
	ELSE 'Alarma'
    END AS comprobacion_mrr_amount
FROM subscriptions
GROUP BY comprobacion_mrr_amount;   #RESULTADO: solo aparecen 2 categorías.
									-- 'Subscripción Normal' (mrr>0, no-trial): 1002
									-- 'Hipótesis positiva'  (mrr=0, trial):     162


-- Verificación 2. -- Discrepancia entre las dos fuentes de churn.
SELECT
	COUNT(*) AS cuentas,
    ROUND(COUNT(*) / (SELECT COUNT(*) FROM estado_churn_cuenta) * 100, 2) AS porcentaje,
    CASE 
		WHEN es_churn = 1 AND churn_flag_origen = 1 THEN 'a. Coinciden: baja'
        WHEN es_churn = 0 AND churn_flag_origen = 0 THEN 'b. Coinciden: activa'
        WHEN es_churn = 1 AND churn_flag_origen = 0 THEN 'c. Discrepan: flag no detecta baja'
        ELSE 'd. Discrepan: flag marca de más' 
        END AS discrepancias_churn
FROM estado_churn_cuenta
GROUP BY discrepancias_churn
ORDER BY discrepancias_churn ASC;


-- Verificación 3. -- Complementaria a la anterior:
#  Cifras base: cuentas activas frente a cuentas dadas de baja.
SELECT
	SUM(CASE WHEN es_churn = 1 THEN 1 END) AS bajas,
    SUM(CASE WHEN es_churn = 0 THEN 1 END) AS activas
FROM estado_churn_cuenta;  -- 119 bajas y 381 activas = 500 cuentas en total. 


-- Verificación 4. -- Consulta/Verificación que cerró la auditoría de datos de RavenStack original: ##--  Uso del producto posterior a la fecha de baja. 
SELECT COUNT(*) AS eventos_post_baja,
       COUNT(DISTINCT ecc.account_id) AS cuentas_afectadas
FROM estado_churn_cuenta ecc
JOIN subscriptions s  ON ecc.account_id = s.account_id
JOIN feature_usage fu ON s.subscription_id = fu.subscription_id
WHERE ecc.es_churn = 1 AND fu.usage_date > ecc.fecha_churn;  -- 0 eventos post baja (encontramos eventos coherentes en este dataset).


/* BLOQUE 1 · ANÁLISIS DEL CHURN */
                                        
-- ============================================================================================================================= 
							-- Pregunta 1 — CUANTIFICACIÓN: ¿cuánto churn hay y cuánto cuesta? -- (Página 37)
-- ============================================================================================================================= 

-- CONSULTA 1 -- Churn por cohorte de antigüedad: Porcentaje de churn de cuentas más antiguas frente a las más recientes. 
 SELECT
	YEAR(a.signup_date) AS año_alta,
    QUARTER(a.signup_date) AS trimestre_alta,
    COUNT(*) AS cuentas,
    SUM(ecc.es_churn) AS bajas,
	ROUND(AVG(ecc.es_churn) * 100, 2) AS porcentaje_churn,
    ROUND(AVG(DATEDIFF(COALESCE(ecc.fecha_churn, '2024-12-31'), a.signup_date)), 0) AS dias_observacion_media
FROM accounts a
JOIN estado_churn_cuenta ecc ON a.account_id = ecc.account_id
GROUP BY año_alta, trimestre_alta
ORDER BY año_alta ASC, trimestre_alta ASC;
 

-- CONSULTA 2 -- Distribución temporal a nivel mensual de las bajas y las altas.

-- Parte 2a -- Distribución mensual de las bajas. Contar las 119 bajas distribuidas mes a mes (usando fecha_churn). 
 SELECT
	DATE_FORMAT(fecha_churn, '%Y-%m') AS fecha_baja,
    COUNT(*) AS bajas
FROM estado_churn_cuenta
WHERE es_churn = 1
GROUP BY fecha_baja
ORDER BY fecha_baja ASC; 

-- Parte 2b --  Altas por mes: ¿cuánto creció la base de clientes cada mes? -- Comparación con la tabla anterior. 
SELECT
	DATE_FORMAT(signup_date, '%Y-%m') AS fecha_alta,
    COUNT(*) AS altas
FROM accounts
GROUP BY fecha_alta
ORDER BY fecha_alta ASC;


-- CONSULTA 3 -- Tiempo de vida hasta la baja.

-- Parte 3a --  Tiempo de vida de las 119 cuentas churneadas. Cálculo del mínimo y el máximo de tiempo. 
WITH vida_cuenta AS (
    SELECT
        DATEDIFF(ecc.fecha_churn, a.signup_date) AS dias,
        NTILE(4) OVER (ORDER BY DATEDIFF(ecc.fecha_churn, a.signup_date)) AS cuartil
    FROM accounts a
    JOIN estado_churn_cuenta ecc ON a.account_id = ecc.account_id
    WHERE ecc.es_churn = 1)
SELECT
    cuartil,
    COUNT(*) AS cuentas,
    MIN(dias) AS dias_desde,
    MAX(dias) AS dias_hasta
FROM vida_cuenta
GROUP BY cuartil
ORDER BY cuartil;

-- Parte 3b --  Cálculo del churn por tramos para saber si las cuentas se van pronto o tarde. 
SELECT
	CASE
		WHEN DATEDIFF(ecc.fecha_churn, a.signup_date) <= 30 THEN 'a. 30 días'
       	WHEN DATEDIFF(ecc.fecha_churn, a.signup_date) <= 90 THEN 'b. 31-90 días'
		WHEN DATEDIFF(ecc.fecha_churn, a.signup_date) <= 180 THEN 'c. 91-180 días'
		WHEN DATEDIFF(ecc.fecha_churn, a.signup_date) <= 365 THEN 'd. 181-365 días'
        ELSE 'e. Más de 1 año'
        END AS tramo_vida_cuenta,
	COUNT(*) AS cuentas,
    ROUND(COUNT(*) / (SELECT COUNT(*) FROM estado_churn_cuenta WHERE es_churn = 1) * 100,2) AS porcentaje
FROM accounts a
JOIN estado_churn_cuenta ecc ON a.account_id = ecc.account_id
WHERE ecc.es_churn = 1
GROUP BY tramo_vida_cuenta
ORDER BY tramo_vida_cuenta; 


-- CONSULTA 4 -- Coste administrativo del churn: suma, media, mínimo y máximo de la cantidad retornada. 
SELECT
	SUM(es_churn) AS bajas,
    SUM(CASE WHEN cantidad_retornada > 0 THEN 1 ELSE 0 END) AS con_reembolso,
	ROUND(AVG(cantidad_retornada),2) AS media_por_baja,
    ROUND(AVG(CASE WHEN cantidad_retornada > 0 THEN cantidad_retornada END), 2) AS media_por_reembolso,
	MIN(CASE WHEN cantidad_retornada > 0 THEN cantidad_retornada END) AS reembolso_minimo,
    MAX(cantidad_retornada) AS reembolso_maximo,
	SUM(cantidad_retornada) AS total_reembolso
FROM estado_churn_cuenta
WHERE es_churn = 1;


-- CONSULTA 5 -- Revenue churn acumulado. (Esta consulta estaba bloqueada en RavenStack original porque las suscripciones canceladas no tenían fecha de cierre). 
WITH revenue_churn_acumulado AS(
	SELECT
		SUM(ecc.es_churn) AS cuentas_churn,
		COUNT(CASE WHEN ecc.es_churn = 1 AND mpc.valor_monetario IS NULL THEN 1 END) AS cuentas_sin_valor,
		SUM(CASE WHEN ecc.es_churn = 1 THEN mpc.valor_monetario END ) AS revenue_perdido,
		SUM(CASE WHEN ecc.es_churn = 0 THEN mpc.valor_monetario END) AS revenue_actual
	FROM estado_churn_cuenta ecc
	JOIN metricas_por_cuenta mpc ON ecc.account_id = mpc.account_id)

	SELECT 
		cuentas_churn,
        cuentas_sin_valor,
        revenue_perdido,
        revenue_actual,
		ROUND(revenue_perdido / (revenue_perdido + revenue_actual) * 100 , 2) AS pct_revenue_churn
	FROM revenue_churn_acumulado;



-- =============================================================================================================================== 
						-- 	Pregunta 2 — CARACTERIZACIÓN: ¿se van logos pequeños o ingresos grandes? -- (Página 41)
-- =============================================================================================================================== 

-- CONSULTA 6 -- Tamaño de las cuentas que se van frente a las que se quedan.
WITH tamaño_cuentas AS (
	SELECT 
		a.account_id,
        a.seats,
        ecc.es_churn,
		NTILE(4) OVER (ORDER BY a.seats) AS grupo
	FROM accounts a
	JOIN estado_churn_cuenta ecc ON a.account_id = ecc.account_id)

SELECT 
	grupo,
	COUNT(*) AS cuentas,
	MIN(seats) desde_num_seats,
	MAX(seats) hasta_num_seats
FROM tamaño_cuentas
GROUP BY grupo
ORDER BY grupo ASC;


-- En esta consulta anterior he particionado los grupos en 4 grupos según tamaño de las cuentas para poder hacer la clasificación siguiente 
-- sin que los rangos sean de forma aleatoria o subjetiva:

SELECT
	CASE 
		WHEN a.seats <= 5 THEN 'a. Cuentas pequeñas'
        WHEN a.seats BETWEEN 5 AND 15 THEN 'b. Cuentas medianas'
		WHEN a.seats BETWEEN 15 AND 28 THEN 'c. Cuentas grandes'
        WHEN a.seats > 28 THEN 'd. Cuentas muy grandes'
        END AS clasificacion_tamaño,
        COUNT(*) AS total_cuentas,
        SUM(es_churn) AS cuentas_churn,
		ROUND(AVG(es_churn) * 100, 2) AS tasa_churn
FROM accounts a
JOIN estado_churn_cuenta ecc ON a.account_id = ecc.account_id
GROUP BY clasificacion_tamaño
ORDER BY clasificacion_tamaño ASC;


-- Consulta 7 -- Concentración del valor.
WITH valor_cuentas AS(
	SELECT
		mpc.valor_monetario,
        ecc.es_churn,
		NTILE(10) OVER (ORDER BY mpc.valor_monetario DESC) AS grupo
	FROM metricas_por_cuenta mpc
	JOIN estado_churn_cuenta ecc ON mpc.account_id = ecc.account_id
	WHERE mpc.valor_monetario IS NOT NULL)  -- Hay 15 cuentas sin valor asignado, este filtro evita ensuciar el resultado.

SELECT 
	grupo,
	COUNT(*) AS cuentas,
    ROUND(SUM(valor_monetario),0) AS valor_arr,
    ROUND(SUM(valor_monetario) / (SELECT SUM(valor_monetario) FROM valor_cuentas) * 100 ,2) AS pct_valor_arr,
    SUM(es_churn) AS cuentas_churn,
    ROUND(AVG(es_churn) * 100, 2) AS tasa_churn,
	ROUND(SUM(CASE WHEN es_churn = 1 THEN valor_monetario END) / (SELECT SUM(CASE WHEN es_churn = 1 THEN valor_monetario END) FROM valor_cuentas) * 100, 2) AS pct_arr_perdido
FROM valor_cuentas
GROUP BY  grupo
ORDER BY  grupo;


-- ============================================================================================================================= 
						  -- Pregunta 3 — CAUSAS: ¿por qué se van y cuánto cuesta cada motivo? -- (Página 43)
-- ============================================================================================================================= 

-- CONSULTA 8 -- Distribución de los motivos de cancelación.
SELECT
	motivo_churn,
	COUNT(*) AS cuentas_churn,
	ROUND(COUNT(*) / (SELECT COUNT(*) FROM estado_churn_cuenta WHERE es_churn = 1) * 100,2) AS porcentaje
FROM estado_churn_cuenta
WHERE es_churn = 1
GROUP BY motivo_churn
ORDER BY porcentaje DESC;

-- CONSULTA 9 -- Coste monetario por motivo de cancelación.
WITH coste_motivo AS(
	SELECT 
		ecc.motivo_churn,
        mpc.valor_monetario
	FROM estado_churn_cuenta ecc
	JOIN metricas_por_cuenta mpc ON ecc.account_id = mpc.account_id
	WHERE ecc.es_churn = 1)
    
SELECT 
	motivo_churn,
	COUNT(*) AS cuentas_churn,
    SUM(valor_monetario IS NULL) AS cuentas_sin_valor, -- tener en cuenta las 3 cuentas sin valor monetario
    ROUND(COUNT(*) / (SELECT COUNT(*) FROM coste_motivo) * 100,2) AS pct_cuentas,
    ROUND(SUM(valor_monetario) ,0) AS arr_perdido,
    ROUND(SUM(valor_monetario) / (SELECT SUM(valor_monetario) FROM coste_motivo) * 100 ,2) AS pct_arr_perdido
FROM coste_motivo 
GROUP BY motivo_churn
ORDER BY pct_arr_perdido DESC;

    
-- CONSULTA 10 -- Motivo de baja cruzado con el tamaño de licencias (seats) de la cuenta.
WITH bajas_clasificadas AS (
    SELECT
		CASE
			WHEN ecc.motivo_churn IN ('features','support') THEN 'Producto'
            WHEN ecc.motivo_churn IN ('pricing', 'budget', 'competitor') THEN 'Comercial'
            ELSE 'Sin especificar'
            END AS familia_motivo,
		CASE
			WHEN a.seats <= 15 THEN 'Pequeñas'
            ELSE 'Grandes'
            END AS tramo_tamaño
    FROM estado_churn_cuenta ecc
	JOIN accounts a ON ecc.account_id = a.account_id
    WHERE ecc.es_churn = 1)

SELECT
	familia_motivo,
    tramo_tamaño,
    COUNT(*) AS cuentas,
	ROUND(COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY familia_motivo) * 100 , 2) AS porcentaje
FROM bajas_clasificadas
GROUP BY familia_motivo, tramo_tamaño
ORDER BY familia_motivo ASC, tramo_tamaño ASC;

-- CONSULTA 11 -- Motivo de baja cruzado con el tiempo de vida de la cuenta.
WITH bajas_clasificadas AS (
    SELECT
		CASE
			WHEN ecc.motivo_churn IN ('features','support') THEN 'Producto'
            WHEN ecc.motivo_churn IN ('pricing', 'budget', 'competitor') THEN 'Comercial'
            ELSE 'Sin especificar'
            END AS familia_motivo,
		CASE
			WHEN DATEDIFF(ecc.fecha_churn, a.signup_date) <= 90 THEN 'a. Temprano'
			WHEN DATEDIFF(ecc.fecha_churn, a.signup_date) BETWEEN 91 AND 365 THEN 'b. Intermedio'
			WHEN DATEDIFF(ecc.fecha_churn, a.signup_date) > 365 THEN 'c. Tardío'
			END AS banda_vida
	FROM estado_churn_cuenta ecc
	JOIN accounts a ON ecc.account_id = a.account_id
    WHERE ecc.es_churn = 1)

SELECT
    familia_motivo,
    banda_vida,
    COUNT(*) AS cuentas,
    ROUND(COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY banda_vida) * 100 , 2) AS porcentaje
FROM bajas_clasificadas
GROUP BY familia_motivo, banda_vida
ORDER BY banda_vida ASC, familia_motivo ASC;


-- CONSULTA 12 -- La prueba de coherencia.

-- Parte 12a -- ¿Quien alega 'features' usaba menos funcionalidades?
WITH cuentas_baja AS (
    SELECT
    ecc.account_id,
    CASE WHEN ecc.motivo_churn = 'features' THEN 1 ELSE 0 END AS alega_features,
	mpc.amplitud_uso,
	mpc.frecuencia_uso
	FROM estado_churn_cuenta ecc
	JOIN metricas_por_cuenta mpc ON ecc.account_id = mpc.account_id
	WHERE ecc.es_churn = 1)
    
SELECT # Queremos una tabla con dos filas:
    alega_features,
    COUNT(*) AS cuentas,
	ROUND(AVG(amplitud_uso), 2) AS amplitud_media,
	ROUND(AVG(frecuencia_uso), 0) AS frecuencia_media
FROM cuentas_baja
GROUP BY alega_features;

-- PARTE B -- ¿Quien alega 'support' tuvo peor experiencia de soporte?
WITH tickets_por_cuenta AS (
	SELECT 
		account_id,
        COUNT(ticket_id) AS num_tickets,
        AVG(resolution_time_hours) AS tiempo_resolucion,
        AVG(satisfaction_score) AS satisfaccion,
        AVG(escalation_flag) AS tasa_escalada
 	FROM support_tickets
    GROUP BY account_id),
    
cuentas_baja AS (
    SELECT
		ecc.account_id,
		CASE WHEN ecc.motivo_churn = 'support' THEN 1 ELSE 0 END alega_soporte,
		tpc.num_tickets,
        tpc.tiempo_resolucion,
        tpc.satisfaccion,
        tpc.tasa_escalada
	FROM estado_churn_cuenta ecc 
    LEFT JOIN tickets_por_cuenta tpc ON ecc.account_id = tpc.account_id
    WHERE ecc.es_churn = 1)
    
SELECT  # En la consulta principal le pedimos que nos devuelva una tabla de dos filas.
		 # Redondeo en la agregación final y no en la primera CTE, así evito acumular errores de redondeo al promediar dos veces
	alega_soporte,
    COUNT(*) AS cuentas,
	ROUND(AVG(num_tickets),2) AS media_num_tickets,
	ROUND(AVG(tiempo_resolucion),1) AS media_horas_resolucion,
	ROUND(AVG(satisfaccion),2) AS media_satisfaccion,
	ROUND(AVG(tasa_escalada) * 100 ,2) AS pct_escalada
FROM cuentas_baja
GROUP BY alega_soporte;


-- ============================================================================================================================= 
							-- 	Pregunta 4 — ANTICIPACIÓN: ¿qué señal temprana anticipa la baja? -- (Página 48)
-- ============================================================================================================================= 

-- CONSULTA 13 -- Señales de comportamiento antes de la baja frente a cuentas activas.
WITH referencia AS (
	# Esta CTE le asigna a cada cuenta su propio punto de observación para entender la recencia:
	-- COALESCE devuelve el primer valor no nulo: 
	-- Si la cuenta se dio de baja --> devuelve su fecha de baja.
	-- Si la cuenta sigue activa --> devuelve la fecha de cierre del periodo.
    SELECT 
		account_id, 
		es_churn,
		COALESCE(fecha_churn, '2024-12-31') AS fecha_referencia 
    FROM estado_churn_cuenta),

actividad_90d AS ( # Ventana de 90 días anteriores a su fecha de referencia es la convención habitual en SaaS (un trimestre)
    SELECT 
		r.account_id, 
        r.es_churn,
		COUNT(fu.id) AS eventos,
		AVG(fu.usage_count) AS intensidad,
		AVG(fu.error_count) AS errores
    FROM referencia r
    LEFT JOIN subscriptions s ON r.account_id = s.account_id
    LEFT JOIN feature_usage fu ON s.subscription_id = fu.subscription_id
	AND fu.usage_date > DATE_SUB(r.fecha_referencia, INTERVAL 90 DAY) -- resta 90 días a la fecha de referencia
	AND fu.usage_date <= r.fecha_referencia
    GROUP BY r.account_id, r.es_churn),

recencia AS ( # Cálculo de valores para cada cuenta (500 filas):
    SELECT r.account_id,
		DATEDIFF(r.fecha_referencia, MAX(fu.usage_date)) AS dias_silencio
    FROM referencia r
    LEFT JOIN subscriptions s ON r.account_id = s.account_id
    LEFT JOIN feature_usage fu ON s.subscription_id = fu.subscription_id
	AND fu.usage_date <= r.fecha_referencia
    GROUP BY r.account_id, r.fecha_referencia)
    
SELECT   # En la consulta principal queremos que se nos devuelva una tabla de solo dos líneas (cuentas activas y cuentas churn)
    a.es_churn,
    COUNT(*) AS cuentas,
    SUM(a.eventos = 0) AS sin_uso_en_90d,
    ROUND(AVG(rec.dias_silencio), 1) AS dias_silencio_medio,
    ROUND(AVG(a.intensidad), 2) AS intensidad_media,
    ROUND(AVG(a.eventos), 1) AS eventos_medios,
    ROUND(AVG(a.errores), 3) AS errores_medios
FROM actividad_90d a
JOIN recencia rec ON a.account_id = rec.account_id
GROUP BY a.es_churn
ORDER BY a.es_churn DESC;


-- CONSULTA 14 -- Actividad y experiencia de soporte previa a la baja. 
WITH referencia AS (
    SELECT 
		account_id, 
		es_churn,
		COALESCE(fecha_churn, '2024-12-31') AS fecha_referencia 
    FROM estado_churn_cuenta),

soporte_90d AS ( # Cálculo de valores para cada cuenta (500 filas):
    SELECT 
		r.account_id, 
        r.es_churn,
		COUNT(st.ticket_id) AS tickets_abiertos,
		AVG(st.resolution_time_hours) AS tiempo_resolucion,
		AVG(st.first_response_time_minutes) AS primera_respuesta,
        AVG(st.satisfaction_score) AS satisfaccion,
        AVG(st.escalation_flag) * 100 AS tasa_escalada
    FROM referencia r
    LEFT JOIN support_tickets st ON r.account_id = st.account_id
	AND st.submitted_at > DATE_SUB(r.fecha_referencia, INTERVAL 90 DAY) 
	AND st.submitted_at <= r.fecha_referencia
    GROUP BY r.account_id, r.es_churn)

SELECT  # En la consulta principal queremos que se nos devuelva una tabla de solo dos líneas (cuentas activas y cuentas churn)
    es_churn,
    COUNT(*) AS cuentas,
    SUM(tickets_abiertos = 0) AS sin_tickets_en_ventana,
    ROUND(AVG(tickets_abiertos), 2) AS tickets_medios,
    ROUND(AVG(tiempo_resolucion), 1) AS horas_resolucion,
    ROUND(AVG(primera_respuesta), 1) AS minutos_1a_respuesta,
    ROUND(AVG(satisfaccion), 2) AS satisfaccion_media,
    ROUND(AVG(tasa_escalada), 2) AS pct_escalada
FROM soporte_90d
GROUP BY es_churn
ORDER BY es_churn;

-- CONSULTA 15 -- El canal de captación como factor de riesgo estructural.
WITH canal AS (
    SELECT
        a.referral_source AS canal,
        ecc.es_churn,
        mpc.valor_monetario AS arr,
        DATEDIFF(COALESCE(ecc.fecha_churn, '2024-12-31'), a.signup_date) AS dias_observacion
    FROM accounts a
    JOIN estado_churn_cuenta ecc  ON a.account_id = ecc.account_id
    JOIN metricas_por_cuenta mpc  ON a.account_id = mpc.account_id)

SELECT
    canal,
    COUNT(*) AS cuentas,
    SUM(es_churn) AS bajas,
    ROUND(AVG(es_churn) * 100, 2) AS tasa_churn,
    ROUND(AVG(dias_observacion), 0) AS dias_observacion,
    ROUND(SUM(CASE WHEN es_churn = 1 THEN arr END), 0) AS arr_perdido,
    ROUND(SUM(CASE WHEN es_churn = 1 THEN arr END)
          / (SELECT SUM(CASE WHEN es_churn = 1 THEN arr END) FROM canal) * 100, 2) AS pct_arr_perdido
FROM canal
GROUP BY canal
ORDER BY tasa_churn DESC;

/* ============================================= Finalización del análisis de churn ================================================ */
