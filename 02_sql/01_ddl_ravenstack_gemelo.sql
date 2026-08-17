/* ===============================================================================
ddl_gemelo.sql | Proyecto Integrador RavenStack
Autora: Marta Quevedo Oltra | Unicorn Edition 13.0
Fase 2. Modelado y creación de la base de datos en MySQL (réplica del original)
 ================================================================================ */

/*_____________________________________________________________________________________________________
NOTA:
Este script está documentado en la memoria del proyecto en el apartado Fase 2 en la página 21.
_______________________________________________________________________________________________________*/

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
