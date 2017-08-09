SET work_mem='8GB';

DROP TABLE IF EXISTS activist_director.activism_events CASCADE;

CREATE TABLE activist_director.activism_events AS

WITH activist_director AS (
    SELECT DISTINCT permno, dissident_group, eff_announce_date,
        min(appointment_date) AS first_appointment_date,
        count(appointment_date) AS num_activist_directors,
        sum((independent IS FALSE)::integer) AS num_affiliate_directors,
        sum((independent IS TRUE)::integer) AS num_unaffiliate_directors
    FROM activist_director.activist_directors
    GROUP BY permno, dissident_group, eff_announce_date
    ORDER BY permno, dissident_group, eff_announce_date),

matched AS (
    SELECT DISTINCT a.*, first_appointment_date,
        num_activist_directors, num_affiliate_directors, num_unaffiliate_directors,
        COALESCE((dissident_board_seats_wongranted_date IS NOT NULL OR dissident_board_seats_won > 0 OR campaign_resulted_in_board_seats_for_activist), FALSE) AS activist_director,
        COALESCE(CASE WHEN (dissident_board_seats_wongranted_date IS NOT NULL OR dissident_board_seats_won > 0 OR campaign_resulted_in_board_seats_for_activist) THEN proxy_fight_went_the_distance ='Yes' END, FALSE) AS elected
    FROM activist_director.activism_sample AS a
    LEFT JOIN activist_director AS b
    ON a.permno=b.permno AND a.eff_announce_date=b.eff_announce_date AND a.dissident_group=b.dissident_group
    ORDER BY permno, dissident_group, eff_announce_date)

SELECT DISTINCT *,
	CASE
            WHEN activist_demand_old THEN TRUE
            WHEN first_board_demand_date IS NOT NULL THEN TRUE
	    ELSE FALSE END AS activist_demand,
	CASE
	    WHEN activist_director THEN 'activist_director'
	    WHEN activist_demand_old THEN 'activist_demand'
            WHEN first_board_demand_date IS NOT NULL THEN 'activist_demand'
	    WHEN activism THEN 'activism'
	    ELSE '_none' END AS category,
	CASE
            WHEN activist_director AND num_affiliate_directors > 0 THEN 'affiliated'
            WHEN activist_director AND num_affiliate_directors = 0 THEN 'non_affiliated'
            WHEN activist_demand_old THEN 'activist_demand'
            WHEN first_board_demand_date IS NOT NULL THEN 'activist_demand'
            WHEN activism THEN 'activism'
            ELSE '_none' END AS affiliated,
	CASE
	    WHEN num_activist_directors > 1 THEN 'two_plus_directors'
	    WHEN activist_director THEN 'one_director'
	    WHEN activist_demand_old THEN 'activist_demand'
            WHEN first_board_demand_date IS NOT NULL THEN 'activist_demand'
	    WHEN activism THEN 'activism'
	    ELSE '_none' END AS two_plus,
	CASE
    	    WHEN first_appointment_date - eff_announce_date <= 180 THEN 'early'
    	    WHEN first_appointment_date - eff_announce_date > 180 THEN 'late'
    	    WHEN activist_demand_old THEN 'activist_demand'
            WHEN first_board_demand_date IS NOT NULL THEN 'activist_demand'
    	    WHEN activism THEN 'activism'
    	    ELSE '_none' END AS early,
	CASE
            WHEN activist_director AND
                market_capitalization_at_time_of_campaign*
                    dissident_group_ownership_percent_at_announcement/100 > 100 THEN 'big investment director'
            WHEN activist_director THEN 'small investment director'
            WHEN activist_demand_old THEN 'activist_demand'
            WHEN first_board_demand_date IS NOT NULL THEN 'activist_demand'
            WHEN activism then 'activism'
            ELSE '_none' END AS big_investment,
    CASE WHEN proxy_fight_went_the_distance AND activist_director THEN 'elected_ad'
			WHEN proxy_fight_went_the_distance AND activist_director IS FALSE THEN 'proxy_fight_failed'
			WHEN proxy_fight_went_the_distance IS FALSE AND activist_director THEN 'settled_ad'
			WHEN proxy_fight_went_the_distance IS FALSE AND activist_director IS FALSE
				AND settled THEN 'settled_no_ad'
			WHEN proxy_fight_went_the_distance IS FALSE AND activist_director IS FALSE AND settled IS FALSE THEN 'failed_activism'
		END AS new_category,
	CASE WHEN proxy_fight_went_the_distance AND activist_director THEN 'elected_ad'
			WHEN proxy_fight_went_the_distance AND activist_director IS FALSE THEN 'proxy_fight_failed'
			WHEN proxy_fight_went_the_distance IS FALSE AND activist_director THEN 'settled_ad'
			WHEN proxy_fight_went_the_distance IS FALSE AND activist_director IS FALSE
				AND concession_made THEN 'settled_no_ad'
			WHEN proxy_fight_went_the_distance IS FALSE AND activist_director IS FALSE AND concession_made IS FALSE
				AND (governance_demands != '{""}' OR value_demands != '{""}') THEN 'failed_activism'
			WHEN proxy_fight_went_the_distance IS FALSE AND activist_director IS FALSE AND concession_made IS FALSE
				AND (governance_demands = '{""}' AND governance_demands = '{""}') THEN NULL
		END AS new_category2
FROM matched
ORDER BY permno, dissident_group, eff_announce_date;

ALTER TABLE activist_director.activism_events OWNER TO activism;
