/* ===========================================================================================
Archivo DDL | Proyecto Integrador RavenStack
Autora: Marta Quevedo Oltra | Unicorn Edition 13.0
Fase 2. Modelado y creación de la base de datos en MySQL (dataset gemelo)

NOTA:
Este script está documentado en la memoria del proyecto en el apartado Fase 2 en la página 21.
 ============================================================================================== */


DROP DATABASE IF EXISTS ravenstack_gemelo;
CREATE DATABASE ravenstack_gemelo CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE ravenstack_gemelo;

-- las cinco CREATE TABLE, en orden:
-- 1. accounts  2. subscriptions  3. feature_usage  4. churn_events  5. support_tickets

CREATE TABLE accounts (
	account_id VARCHAR(20) PRIMARY KEY,
	account_name VARCHAR(100) NOT NULL,
	industry ENUM ('EdTech', 'FinTech', 'DevTools', 'HealthTech', 'Cybersecurity') NOT NULL,
	country CHAR(2) NOT NULL,
	signup_date DATE NOT NULL,
	referral_source ENUM ('partner', 'other', 'organic', 'event', 'ads') NOT NULL,
	plan_tier ENUM ('Basic', 'Pro', 'Enterprise') NOT NULL,
	seats SMALLINT UNSIGNED NOT NULL,
	is_trial BOOL NOT NULL,
	churn_flag BOOL NOT NULL -- se conserva para fidelizar al máximo el análisis
) ENGINE=InnoDB;

CREATE TABLE subscriptions (
subscription_id VARCHAR(20) PRIMARY KEY,
account_id VARCHAR(20) NOT NULL, 
start_date DATE NOT NULL,
end_date DATE,  -- para las suscripciones sin fecha de finalización la columna debe aceptar nulos (legítimos). 
plan_tier ENUM ('Basic', 'Pro', 'Enterprise') NOT NULL,
seats SMALLINT UNSIGNED NOT NULL,
mrr_amount DECIMAL(10,2) NOT NULL,
arr_amount DECIMAL(10,2) NOT NULL,
is_trial BOOL NOT NULL,
upgrade_flag BOOL NOT NULL,	
downgrade_flag BOOL NOT NULL,
churn_flag BOOL NOT NULL,
billing_frequency ENUM ('monthly', 'annual') NOT NULL,
auto_renew_flag BOOL NOT NULL,
CONSTRAINT fk_subscriptions FOREIGN KEY (account_id)
    REFERENCES accounts(account_id) ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE feature_usage (
id INT AUTO_INCREMENT PRIMARY KEY,  -- clave sustituta generada por MySQL
usage_id VARCHAR(20) NOT NULL,  -- identificador de origen (duplicados conocidos)
subscription_id VARCHAR(20) NOT NULL,
usage_date DATE NOT NULL,
feature_name VARCHAR(50) NOT NULL,
usage_count SMALLINT UNSIGNED NOT NULL,
usage_duration_secs SMALLINT UNSIGNED NOT NULL,
error_count SMALLINT UNSIGNED NOT NULL,
is_beta_feature BOOL NOT NULL,
 CONSTRAINT fk_usage_subscription FOREIGN KEY (subscription_id)
        REFERENCES subscriptions(subscription_id) ON DELETE RESTRICT
) ENGINE=InnoDB;


CREATE TABLE churn_events (
churn_event_id VARCHAR(20) PRIMARY KEY,
account_id VARCHAR(20) NOT NULL,
churn_date DATE NOT NULL,
reason_code ENUM ('pricing', 'support', 'budget', 'features', 'competitor', 'unknown') NOT NULL,
refund_amount_usd DECIMAL (10,2) NOT NULL,
preceding_upgrade_flag BOOL NOT NULL,
preceding_downgrade_flag BOOL NOT NULL,
is_reactivation BOOL NOT NULL,
feedback_text VARCHAR(255),
CONSTRAINT fk_churn_events FOREIGN KEY (account_id)
    REFERENCES accounts(account_id) ON DELETE RESTRICT
) ENGINE=InnoDB;


CREATE TABLE support_tickets (
ticket_id VARCHAR(20) PRIMARY KEY,
account_id VARCHAR(20) NOT NULL,
submitted_at DATETIME NOT NULL,
closed_at DATETIME NOT NULL,
resolution_time_hours FLOAT NOT NULL,
priority ENUM ('low','medium','high','urgent') NOT NULL,
first_response_time_minutes SMALLINT UNSIGNED NOT NULL,
satisfaction_score TINYINT UNSIGNED,
escalation_flag BOOL NOT NULL,
CONSTRAINT fk_support_tickets FOREIGN KEY (account_id)
    REFERENCES accounts(account_id) ON DELETE RESTRICT
) ENGINE=InnoDB;
/* ============================================= Finalización archivo DDL ================================================ */



USE ravenstack_gemelo;

/* 
===============================================================================================================================
VISTAS BASE PARA EL ANÁLISIS | Proyecto Integrador RavenStack
Autora: Marta Quevedo Oltra | Unicorn Edition 13.0
Fase 5. Diagnóstico del churn (sobre dataset gemelo)

NOTA:
Este script queda comentado en una pequeña nota en la memoria del proyecto, al principio del apartado Fase 5 (página 36).
===============================================================================================================================
*/

/* 
   FUENTE ÚNICA DE VERDAD SOBRE EL CHURN

	-- VISTA 1 -  estado_churn_cuenta .  (Idéntica a la creada para el dataset Ravenstack original. No se modifica ni una línea)
   */

CREATE OR REPLACE VIEW estado_churn_cuenta AS 

WITH eventos_ordenados AS (
	SELECT
		account_id,
        churn_event_id,
        churn_date,
        is_reactivation,
        reason_code,
        refund_amount_usd,
		ROW_NUMBER() OVER (PARTITION BY account_id ORDER BY churn_date DESC, is_reactivation ASC, churn_event_id DESC) AS ranking,
        COUNT(*) OVER (PARTITION BY account_id) AS num_eventos,
        SUM(is_reactivation) OVER (PARTITION BY account_id) AS num_reactivaciones
	FROM churn_events),
    
estado_final AS (
	SELECT *
	FROM eventos_ordenados
    WHERE ranking = 1)
  
SELECT
	a.account_id,
    COALESCE(ef.num_eventos, 0) AS n_eventos,
    COALESCE(ef.num_reactivaciones, 0) AS reactivaciones,
    CASE 
		WHEN ef.account_id IS NULL THEN 0
        WHEN ef.is_reactivation = 1 THEN 0
        ELSE 1 END AS es_churn,
    CASE WHEN ef.is_reactivation = 0 THEN ef.churn_date END AS fecha_churn,
	CASE WHEN ef.is_reactivation = 0 THEN ef.reason_code END AS motivo_churn,
    CASE WHEN ef.is_reactivation = 0 THEN ef.refund_amount_usd END AS cantidad_retornada,
    a.churn_flag AS churn_flag_origen
FROM accounts a
LEFT JOIN estado_final ef ON a.account_id = ef.account_id;


/* 
  -- VISTA 2 --  metricas_por_cuenta. Esta nueva vista muestra el comportamiento y valor del usuario.
  */

CREATE OR REPLACE VIEW metricas_por_cuenta AS
-- Momento en que se evalua cada cuenta: su baja, o el cierre del periodo.
WITH fechas_referencia AS ( 
    SELECT
        account_id,
        COALESCE(fecha_churn, '2024-12-31') AS fecha_ref,
        DATE_SUB(COALESCE(fecha_churn, '2024-12-31'), INTERVAL 15 DAY) AS fecha_valor
    FROM estado_churn_cuenta),

-- ARR vivo en la fecha de referencia de cada cuenta.
metrica_monetary AS ( 
    SELECT
        fr.account_id,
        SUM(s.mrr_amount) AS ingresos_mensuales,
        SUM(s.arr_amount) AS valor_monetario
    FROM fechas_referencia fr
    JOIN subscriptions s ON fr.account_id = s.account_id
    WHERE s.start_date <= fr.fecha_valor
      AND (s.end_date IS NULL OR s.end_date >= fr.fecha_valor)
    GROUP BY fr.account_id),

metrica_uso AS (
    SELECT
        s.account_id,
        DATEDIFF('2024-12-31', MAX(fu.usage_date)) AS recencia,
        SUM(fu.usage_count) AS frecuencia_uso,
        COUNT(DISTINCT fu.feature_name) AS amplitud_uso,
        ROUND(AVG(fu.error_count), 3) AS errores_por_evento
    FROM feature_usage fu
    INNER JOIN subscriptions s ON fu.subscription_id = s.subscription_id
    GROUP BY s.account_id)

SELECT
    a.account_id,
    mu.recencia,            
    mu.frecuencia_uso,
    mu.amplitud_uso,
    mu.errores_por_evento,
    mm.ingresos_mensuales,
    mm.valor_monetario
FROM accounts a
LEFT JOIN metrica_monetary mm ON a.account_id = mm.account_id
LEFT JOIN metrica_uso mu ON a.account_id = mu.account_id;


/* 
   VERIFICACIONES DE LAS DOS VISTAS
  */

-- Verificación 1 -- Ambas vistas contienen las 500 cuentas:
SELECT 'estado_churn_cuenta' AS vista, COUNT(*) AS filas FROM estado_churn_cuenta
UNION ALL
SELECT 'metricas_por_cuenta', COUNT(*) FROM metricas_por_cuenta;

-- Verificación 2 -- Tasa de churn del gemelo:
SELECT
    es_churn,
    COUNT(*) AS cuentas,
    ROUND(COUNT(*) / (SELECT COUNT(*) FROM estado_churn_cuenta) * 100, 2) AS porcentaje
FROM estado_churn_cuenta
GROUP BY es_churn;  #23,80% de churn

-- Verificación 3 -- Qué cubre 'valor_monetario': cuántas cuentas quedan sin valor.
SELECT
    ecc.es_churn,
    COUNT(*) AS cuentas,
    SUM(CASE WHEN mpc.valor_monetario IS NULL THEN 1 ELSE 0 END) AS sin_valor
FROM estado_churn_cuenta ecc
JOIN metricas_por_cuenta mpc ON ecc.account_id = mpc.account_id
GROUP BY ecc.es_churn;  # 15 cuentas sin valor: 3 churned y 12 activas


/* ============================================= Finalización de las vistas usadas para el análisis de churn ================================================ */




/* 
=============================================================================================================================== 
VISTAS PARA SISTEMA ALERTA Y RECOMENDADOR | Proyecto Integrador RavenStack
Autora: Marta Quevedo Oltra | Unicorn Edition 13.0
Fase 6. Sistema de alerta temprana y recomendador de funcionalidades (Ravenstack_gemelo)

NOTA: 
Este script está dedicado a elaborar pieza a pieza el sistema de alerta temprana sobre las señales detectadas en la fase 
anterior y finaliza con un recomendador de funcionalidades que todavía no han usado para las cuentas vivas calificadas como en riesgo.

Este script tiene una arquitectura de código repartida en dos partes y consiste en 5 piezas de código:

-- SISTEMA DE ALERTA TEMPRANA: 
							PIEZA 1. metricas_riesgo_cuenta      →  las señales de churn de cada cuenta viva
							PIEZA 2. puntuacion_riesgo_cuenta    →  las señales convertidas en puntos (ranking de riesgo)
							PIEZA 3. cartera_clientes_priorizada →  cruce de riesgo de churn por el valor expuesto de la cuenta
							PIEZA 4. La validación               →  sirve para comprobar que el sistema de alerta funciona


RECOMENDADOR DE FEATURES: 
							PIEZA 5. recomendador_funcionalidades →  qué proponerle a cada cuenta señalada como en riesgo
    
    
Todo este código quedan documentados e interpretados en la memoria del proyecto a partir del apartado Fase 6 (página 53).
=============================================================================================================================== 
 */
 

/*  -- PIEZA 1 -- VISTA QUE RECOGE LAS SEÑALES DE LA CARTERA DE CUENTAS QUE SIGUEN VIVAS  */   -- página 54

CREATE OR REPLACE VIEW metricas_riesgo_cuenta AS

WITH cartera_viva AS( 
	SELECT
		account_id,
		DATE('2024-12-31') AS fecha_corte
	FROM estado_churn_cuenta
	WHERE es_churn = 0),   -- 381 cuentas vivas

uso_90d AS(
	SELECT
		cv.account_id,
        COUNT(fu.id) AS sesiones,
        AVG(fu.usage_count) AS intensidad,
        AVG(fu.error_count) AS errores
    FROM cartera_viva cv
    LEFT JOIN subscriptions s ON cv.account_id = s.account_id
    LEFT JOIN feature_usage fu ON s.subscription_id = fu.subscription_id
								AND fu.usage_date > DATE_SUB(cv.fecha_corte, INTERVAL 90 DAY)
                                AND fu.usage_date <= cv.fecha_corte
	GROUP BY cv.account_id),
    
soporte_90d AS(
	SELECT
		cv.account_id,
        COUNT(st.ticket_id) AS incidencias,
        AVG(st.resolution_time_hours) AS tiempo_resolucion,
        AVG(st.satisfaction_score) AS satisfaccion,
        AVG(st.escalation_flag) * 100  AS escalado
	FROM cartera_viva cv
    LEFT JOIN support_tickets st ON cv.account_id = st.account_id
								AND st.submitted_at > DATE_SUB(cv.fecha_corte, INTERVAL 90 DAY)
                                AND st.submitted_at <= cv.fecha_corte
	GROUP BY cv.account_id)
    
SELECT
	cv.account_id,
    COALESCE(uso.intensidad, 0) AS intensidad,
    COALESCE(uso.sesiones, 0) AS sesiones,
    COALESCE(uso.errores, 0) AS errores,
    soporte.incidencias,
    soporte.tiempo_resolucion,
    soporte.escalado,
    soporte.satisfaccion
FROM cartera_viva cv
JOIN uso_90d uso ON cv.account_id = uso.account_id
JOIN soporte_90d soporte ON cv.account_id = soporte.account_id;



/*  -- PIEZA 2 -- VISTA QUE RECOGE LAS SEÑALES DE LA CARTERA VIVA Y LAS PUNTÚA  */ -- página 55

CREATE OR REPLACE VIEW puntuacion_riesgo_cuenta AS

WITH terciles_producto AS(
	SELECT
		account_id,
        NTILE(3) OVER (ORDER BY intensidad ASC) AS tercil_intensidad,
        NTILE(3) OVER (ORDER BY sesiones ASC) AS tercil_sesiones,
        NTILE(3) OVER (ORDER BY errores DESC) AS tercil_errores
	FROM metricas_riesgo_cuenta),

puntos_por_señal AS (
	SELECT
		mrc.account_id,
        3 - tp.tercil_intensidad AS p_intensidad,
        3 - tp.tercil_sesiones AS p_sesiones,
        3 - tp.tercil_errores AS p_errores,
        CASE 
			WHEN mrc.incidencias >= 3 THEN 2 
            WHEN mrc.incidencias >= 1 THEN 1
            ELSE 0 END AS p_incidencias,
		CASE
			WHEN mrc.escalado IS NULL THEN 0
			WHEN mrc.escalado > 25 THEN 2
            WHEN mrc.escalado > 0 THEN 1
            ELSE 0 
		END AS p_escalado,
		CASE 
			WHEN mrc.satisfaccion IS NULL THEN 0
            WHEN mrc.satisfaccion < 3 THEN 2 
            WHEN mrc.satisfaccion < 4 THEN 1
            ELSE 0 
		END AS p_satisfaccion
	
	FROM metricas_riesgo_cuenta mrc
    JOIN terciles_producto tp ON mrc.account_id = tp.account_id)
    
SELECT
	account_id,
    p_intensidad,
    p_sesiones,
    p_errores,
    p_incidencias,
    p_escalado,
    p_satisfaccion,
    p_intensidad + p_sesiones + p_errores AS puntos_producto,
    p_incidencias + p_escalado + p_satisfaccion AS puntos_soporte,
    p_intensidad + p_sesiones + p_errores + p_incidencias + p_escalado + p_satisfaccion AS puntos_totales
FROM puntos_por_señal;


-- CONSULTA EXPLORATORIA -- ¿Cuántas cuentas en riesgo importante tenemos? 
SELECT
    COUNT(CASE WHEN puntos_totales >= 8 THEN 1 END) AS riesgo_alto,
    COUNT(CASE WHEN puntos_totales >= 5 THEN 1 END) AS riesgo_medio,
    COUNT(CASE WHEN puntos_totales < 5 THEN 1 END) AS cuentas_estables
FROM puntuacion_riesgo_cuenta;




/*  -- PIEZA 3 -- VISTA MATRIZ QUE PRIORIZA LAS CUENTAS POR EL VALOR EXPUESTO */ -- página 55

CREATE OR REPLACE VIEW cartera_clientes_priorizada AS 

WITH valor_cartera AS(
	SELECT
		prc.account_id,
        mpc.valor_monetario AS arr,
        NTILE(10) OVER (ORDER BY mpc.valor_monetario DESC) AS decil_valor  -- Queremos que el decil 1 sean las cuentas de mayor valor arr, por eso DESC
	FROM puntuacion_riesgo_cuenta prc
    JOIN metricas_por_cuenta mpc ON prc.account_id = mpc.account_id
    WHERE mpc.valor_monetario IS NOT NULL), 

clasificacion AS(
	SELECT
		prc.account_id,
        prc.puntos_totales,
        prc.puntos_producto,
        prc.puntos_soporte,
        vc.arr,
        vc.decil_valor,
        CASE
			WHEN prc.puntos_totales >= 8 THEN 'Alto'
            WHEN prc.puntos_totales >= 5 THEN 'Medio'
            ELSE 'Bajo'
		END AS nivel_riesgo,
		CASE 
			WHEN vc.decil_valor <= 3 THEN 'Alto'
            WHEN vc.decil_valor <= 7 THEN 'Medio'
            ELSE 'Bajo'
		END AS nivel_valor,
        CASE 
			WHEN prc.puntos_totales >= 8 THEN 1
            WHEN prc.puntos_totales >= 5 THEN 2
            ELSE 3
		END AS orden_riesgo,
        CASE 
			WHEN vc.decil_valor <= 3 THEN 1
            WHEN vc.decil_valor <= 7 THEN 2
            ELSE 3 
		END AS orden_valor
	FROM puntuacion_riesgo_cuenta prc
    JOIN valor_cartera vc ON prc.account_id = vc.account_id)
    
SELECT
	account_id,
    nivel_riesgo,
    orden_riesgo,
    nivel_valor,
    orden_valor,
    puntos_totales,
    puntos_producto,
    puntos_soporte,
    arr,
    CASE
		WHEN nivel_riesgo = 'Alto' AND nivel_valor = 'Alto' THEN '1. Intervencion directa'
        WHEN nivel_riesgo = 'Alto' AND nivel_valor = 'Medio' THEN '2. Contacto proactivo'
        WHEN nivel_riesgo = 'Medio' AND nivel_valor = 'Alto' THEN '2. Contacto proactivo'
		WHEN nivel_riesgo = 'Alto' AND nivel_valor = 'Bajo' THEN '3. Campaña automatizada'
        WHEN nivel_riesgo = 'Medio' AND nivel_valor = 'Medio' THEN '3. Campaña automatizada'
        ELSE '4. Sin accion'
	END AS accion
FROM clasificacion;

SHOW ERRORS;




/*  -- PIEZA 4 -- LA VALIDACIÓN --> ¿Funciona el sistema?   -- página 56

Procedimiento: 
-- 1. Nos situamos en el 30-06-2024.
-- 2. Puntuamos la cartera usando ÚNICAMENTE información anterior a esa fecha. 
-- 3. Se comprueba quién se dio de baja en los 180 días siguientes.  

Se trata de comprobar si el sistema funciona en caso de haber existido en junio (en el  pasado) : ¿habría señalado a las cuentas correctas?

Esta consulta reutiliza mucho código de las vistas anteriores pero con otra fecha de corte y otra definición de cartera viva (la de junio, no la de hoy).
*/

WITH cartera_en_el_corte AS (
	SELECT
		ecc.account_id,
		DATE('2024-06-30') AS fecha_corte,
		CASE
			WHEN ecc.es_churn = 1
			 AND ecc.fecha_churn >= '2024-06-30'
			 AND ecc.fecha_churn <  DATE_ADD('2024-06-30', INTERVAL 180 DAY)
			THEN 1 ELSE 0
		END AS se_fue_despues -- la respuesta que el sistema debía adivinar
	FROM estado_churn_cuenta ecc
	JOIN accounts a ON ecc.account_id = a.account_id
	WHERE (ecc.es_churn = 0 OR ecc.fecha_churn >= '2024-06-30') -- viva EN JUNIO
	  AND a.signup_date <= DATE_SUB('2024-06-30', INTERVAL 60 DAY)), -- con historial

uso_90d AS (
	SELECT
		cec.account_id,
		COUNT(fu.id) AS sesiones,
		AVG(fu.usage_count) AS intensidad,
		AVG(fu.error_count) AS errores
	FROM cartera_en_el_corte cec
	LEFT JOIN subscriptions s ON cec.account_id = s.account_id
	LEFT JOIN feature_usage fu ON s.subscription_id = fu.subscription_id
								AND fu.usage_date >  DATE_SUB(cec.fecha_corte, INTERVAL 90 DAY)
								AND fu.usage_date <= cec.fecha_corte
	GROUP BY cec.account_id),

soporte_90d AS (
	SELECT
		cec.account_id,
		COUNT(st.ticket_id) AS incidencias,
		AVG(st.satisfaction_score) AS satisfaccion,
		AVG(st.escalation_flag) * 100 AS escalado
	FROM cartera_en_el_corte cec
	LEFT JOIN support_tickets st ON cec.account_id = st.account_id
								AND st.submitted_at >  DATE_SUB(cec.fecha_corte, INTERVAL 90 DAY)
								AND st.submitted_at <= cec.fecha_corte
	GROUP BY cec.account_id),

metricas_en_el_corte AS (
	SELECT
		cec.account_id,
		cec.se_fue_despues,
		COALESCE(uso.intensidad, 0) AS intensidad,
		COALESCE(uso.sesiones, 0) AS sesiones,
		COALESCE(uso.errores, 0) AS errores,
		soporte.incidencias,
		soporte.escalado,
		soporte.satisfaccion
	FROM cartera_en_el_corte cec
	JOIN uso_90d uso ON cec.account_id = uso.account_id
	JOIN soporte_90d soporte ON cec.account_id = soporte.account_id),

terciles_producto AS (
	SELECT
		account_id,
		NTILE(3) OVER (ORDER BY intensidad ASC) AS tercil_intensidad,
		NTILE(3) OVER (ORDER BY sesiones ASC) AS tercil_sesiones,
		NTILE(3) OVER (ORDER BY errores DESC) AS tercil_errores
	FROM metricas_en_el_corte),

puntuacion_en_el_corte AS (
	SELECT
		mec.account_id,
		mec.se_fue_despues,
		(3 - tp.tercil_intensidad) + (3 - tp.tercil_sesiones) + (3 - tp.tercil_errores)
	  + CASE
			WHEN mec.incidencias >= 3 THEN 2
			WHEN mec.incidencias >= 1 THEN 1
			ELSE 0 END
	  + CASE
			WHEN mec.escalado IS NULL THEN 0
			WHEN mec.escalado > 25 THEN 2
			WHEN mec.escalado > 0 THEN 1
			ELSE 0 END
	  + CASE
			WHEN mec.satisfaccion IS NULL THEN 0
			WHEN mec.satisfaccion < 3 THEN 2
			WHEN mec.satisfaccion < 4 THEN 1
			ELSE 0 
		END AS puntos_totales
	FROM metricas_en_el_corte mec
	JOIN terciles_producto tp ON mec.account_id = tp.account_id)

SELECT
	CASE
		WHEN puntos_totales >= 8 THEN 'Alto'
		WHEN puntos_totales >= 5 THEN 'Medio'
		ELSE 'Bajo'
	END AS nivel_riesgo,
	COUNT(*) AS cuentas,
	SUM(se_fue_despues) AS bajas_en_180d,
	ROUND(AVG(se_fue_despues) * 100, 2) AS tasa_baja_pct,
	ROUND(AVG(se_fue_despues) / (SELECT AVG(se_fue_despues) FROM puntuacion_en_el_corte), 2) AS lift
FROM puntuacion_en_el_corte
GROUP BY nivel_riesgo
ORDER BY FIELD(nivel_riesgo, 'Alto', 'Medio', 'Bajo');




/*  -- PIEZA 5 -- VISTA RECOMENDADOR DE FUNCIONALIDADES  */ -- página 57

CREATE OR REPLACE VIEW recomendador_funcionalidades AS

WITH uso_por_cuenta AS( -- BLOQUE 1 -- devuelve las funcionalidades que ha tocado cada cuenta y si esa cuenta es de riesgo o no
	SELECT DISTINCT 
		ccp.account_id,
        ccp.nivel_riesgo,
        fu.feature_name
	FROM cartera_clientes_priorizada ccp
    JOIN subscriptions s ON ccp.account_id = s.account_id
    JOIN feature_usage fu ON s.subscription_id = fu.subscription_id),

brecha_funcionalidad AS( -- BLOQUE 2 -- para cada funcionalidad calcula qué porcentaje de cuentas sanas la usa y de en riesgo la usa y se queda con las que tienen brecha de separación de uso. 
	SELECT
		feature_name,
		ROUND(COUNT(DISTINCT CASE WHEN nivel_riesgo = 'Bajo' THEN account_id END) * 100 / (SELECT COUNT(*) FROM cartera_clientes_priorizada WHERE nivel_riesgo = 'Bajo') , 2) AS adopcion_sanas,
		ROUND(COUNT(DISTINCT CASE WHEN nivel_riesgo <> 'Bajo' THEN account_id END) * 100 / (SELECT COUNT(*) FROM cartera_clientes_priorizada WHERE nivel_riesgo <> 'Bajo') ,2) AS adopcion_riesgo
	FROM uso_por_cuenta
    GROUP BY feature_name
    HAVING adopcion_sanas - adopcion_riesgo > 14.83), -- todas las funcionalidades tienen brecha positiva pero 14.83 es la brecha de amplitud repartida entre las 40 funcionalidades disponibles, 
													-- el HAVING descarta del recomendador las funcionalidades que no superan esa referencia.

propuestas AS( -- BLOQUE 3 -- junta todo y produce la lista de funcionalidades a recomendar.
	SELECT
		ccp.account_id,
        ccp.nivel_riesgo,
        ccp.accion,
        ccp.arr,
        bf.feature_name,
        bf.adopcion_sanas,
        bf.adopcion_riesgo,
        ROUND(bf.adopcion_sanas - bf.adopcion_riesgo, 2) AS brecha,
        ROW_NUMBER() OVER (PARTITION BY ccp.account_id ORDER BY bf.adopcion_sanas - bf.adopcion_riesgo DESC, bf.feature_name) AS ORDEN -- numera las candidatas de cada cuenta ordenadas por brecha descendente
	FROM cartera_clientes_priorizada ccp
    CROSS JOIN brecha_funcionalidad bf
    LEFT JOIN uso_por_cuenta upc ON ccp.account_id = upc.account_id AND bf.feature_name = upc.feature_name
    WHERE ccp.accion <> '4. Sin accion' AND upc.feature_name IS NULL)

SELECT
	account_id,
    nivel_riesgo,
    arr,
    accion,
    feature_name,
    adopcion_sanas,
    orden
FROM propuestas
WHERE orden <= 3; -- nos quedamos con las 3 primeras para cada cuenta



-- Consulta -- ¿ Cuantas veces se recomienda cada funcionalidad? 
SELECT DISTINCT feature_name,
	COUNT(DISTINCT account_id) AS cuentas
FROM recomendador_funcionalidades
GROUP BY feature_name
ORDER BY cuentas DESC;

/* ============================================= Finalización vistas para sistema alerta temprana y recomendador  ================================================ */




/* 
=============================================================================================================================== 
VISTAS PARA POWER BI | Proyecto Integrador RavenStack
Autora: Marta Quevedo Oltra | Unicorn Edition 13.0
Fase 7. Visualizacion en Power BI (Ravenstack_gemelo)

NOTA: 
Este script existe con dos propósitos:

-- 1. -- Facilitar el modelado de datos en Power BI, ahorrando el trabajo de combinar tablas dentro del mismo. 
 Por ello se combinan todas las vistas creadas con anterioridad en una sola tabla de hechos (a excepción de la vista recomendador que trabaja a parte). 

-- 2. -- La segunda vista se crea porque las altas y bajas son dos fechas distintas en la misma cuenta. 
En Power BI, un calendario solo puede conectarse a una fecha a la vez y resolviéndolo aquí y agregando por mes
la serie llega a Power BI hecha. 

Todos los LEFT JOIN son para conservar las cuentas perdidas aunque no tengan puntuación de riesgo.
    
-- Todo este código quedan documentado e interpretado en la memoria del proyecto a partir del apartado Fase 7 (página 58).
=============================================================================================================================== 
 */

-- 1. -- Creación de una vista (tabla de hechos), con una fila por cuenta con todo lo que el dashboard necesita:

CREATE OR REPLACE VIEW bi_hechos_cuenta AS

SELECT
	ecc.account_id, 
    ecc.es_churn AS es_baja,
    CASE WHEN ecc.es_churn = 1 THEN 'Perdida' ELSE 'Activa' END AS estado_cuenta,
    ecc.fecha_churn AS fecha_baja,
    ecc.motivo_churn AS motivo_baja,
    mpc.valor_monetario AS facturacion,
	mrc.intensidad,
    mrc.sesiones,
    mrc.errores,
    mrc.incidencias,
    mrc.tiempo_resolucion,
    mrc.escalado,
    mrc.satisfaccion,
    prc.puntos_producto,
    prc.puntos_soporte,
    prc.puntos_totales,
    ccp.nivel_riesgo,
    ccp.orden_riesgo,
    ccp.nivel_valor,
    ccp.orden_valor,
    ccp.accion
FROM estado_churn_cuenta ecc
LEFT JOIN metricas_por_cuenta mpc ON ecc.account_id = mpc.account_id
LEFT JOIN metricas_riesgo_cuenta mrc ON ecc.account_id = mrc.account_id
LEFT JOIN puntuacion_riesgo_cuenta prc ON ecc.account_id = prc.account_id
LEFT JOIN cartera_clientes_priorizada ccp ON ecc.account_id = ccp.account_id;


-- 2. -- Creación de una vista con las altas y las bajas por mes, ya agregadas.

CREATE OR REPLACE VIEW bi_altas_bajas_mes AS

SELECT
	mes,
    SUM(altas) AS altas,
    SUM(bajas) AS bajas
FROM (
    SELECT DATE_FORMAT(signup_date, '%Y-%m-01') AS mes, 1 AS altas, 0 AS bajas
    FROM accounts
    UNION ALL
    SELECT DATE_FORMAT(fecha_churn, '%Y-%m-01'), 0, 1
    FROM estado_churn_cuenta WHERE es_churn = 1
) t

GROUP BY mes
ORDER BY mes ASC;

/* ============================================= Finalización creación de vistas para Power BI  ================================================ */
