DROP TABLE IF EXISTS activist_director.activism_events CASCADE;

CREATE TABLE activist_director.activism_events AS
WITH sharkwatch_raw AS (
    SELECT DISTINCT campaign_id, cusip_9_digit, announce_date,
        synopsis_text,
        least(announce_date, date_original_13d_filed) AS eff_announce_date,
        dissident_group,
        classified_board='Yes' AS classified_board,
        array_remove(regexp_split_to_array(
        regexp_replace(dissident_group_with_sharkwatch50, 'Dissident Group: ', '', 'g'),
                       '\s+SharkWatch50\?:\s+(Yes|No)'),'') AS dissidents,
        activism_type, primary_campaign_type, secondary_campaign_type,
        dissident_board_seats_sought,
        dissident_board_seats_won,
        campaign_resulted_in_board_seats_for_activist='Yes' AS campaign_resulted_in_board_seats_for_activist,
        campaign_status, stock_exchange_primary, primary_sic_code,
        s13d_filer='Yes' AS s13d_filer,
        dissident_group_includes_sharkwatch50_member='Yes' AS sharkwatch50,
        holder_type, company_name, country,
        dissident_group_ownership_percent,
        dissident_group_ownership_percent_at_announcement,
        date_original_13d_filed, proxy_fight_announce_date,
        meeting_date, dissident_board_seats_wongranted_date,
        end_date, state_of_headquarters,
        market_capitalization_at_time_of_campaign, factset_industry,
        LEAST(proxy_fight_announce_date, announce_date) AS first_date,
        GREATEST(meeting_date, end_date) AS last_date,
        proxy_fight='Yes' AS proxy_fight,
        proxy_fight_went_definitive='Yes' AS proxy_fight_went_definitive,
        proxy_fight_went_the_distance='Yes' AS proxy_fight_went_the_distance,
        outcome,
        COALESCE(activism_type='Proxy Fight'
            OR dissident_board_seats_sought > 0
            OR dissident_board_seats_won > 0
            OR primary_campaign_type IN
                ('Withhold Vote for Director(s)',
                'Board Representation',
                'Board Control',
                'Remove Director(s), No Dissident Nominee to Fill Vacancy'),
            FALSE) AS board_related,

        -- I don't think we need this field,
        -- as our activist_directors data should be definitive.
        -- CASE WHEN dissident_board_seats_won > 0 OR
        --    campaign_resulted_in_board_seats_for_activist='Yes' OR
        --    dissident_board_seats_wongranted_date IS NOT NULL
        -- THEN TRUE ELSE FALSE END AS activist_director,
        primary_campaign_type IN
            ('Board Representation', 'Board Control') OR
            dissident_board_seats_sought > 0 OR
            dissident_board_seats_won > 0 OR
            campaign_resulted_in_board_seats_for_activist='Yes' OR
            dissident_board_seats_wongranted_date IS NOT NULL AS activist_demand_old

        FROM factset.sharkwatch_new AS a
        WHERE country='United States'
        AND state_of_incorporation != 'Non-U.S.'
        AND factset_industry != 'Investment Trusts/Mutual Funds'
        AND (s13d_filer='Yes' OR proxy_fight='Yes'
             OR holder_type IN ('Hedge Fund Company', 'Investment Adviser'))
        AND holder_type NOT IN ('Corporation')
        AND campaign_status='Closed'
        AND least(announce_date, date_original_13d_filed) >= '2004-01-01'
        AND least(announce_date, date_original_13d_filed) <= '2012-12-31'
        AND activism_type != '13D Filer - No Publicly Disclosed Activism'),

sharkwatch_agg AS (
    SELECT cusip_9_digit, eff_announce_date, dissident_group, dissidents,
        array_agg(campaign_id) AS campaign_ids,
        string_agg(synopsis_text, ' ') AS synopsis_text,
        bool_or(activist_demand_old) AS activist_demand_old,
        bool_or(board_related) AS board_related,
        bool_or(proxy_fight) AS proxy_fight,
        bool_or(proxy_fight_went_definitive) AS proxy_fight_went_definitive,
        bool_or(proxy_fight_went_the_distance) AS proxy_fight_went_the_distance,
        bool_or(campaign_resulted_in_board_seats_for_activist)
            AS campaign_resulted_in_board_seats_for_activist,
        bool_or(sharkwatch50) AS sharkwatch50,
        bool_or(s13d_filer) AS s13d_filer,
        max(last_date) AS last_date,
        min(last_date) AS first_date,
        min(dissident_board_seats_wongranted_date) AS dissident_board_seats_wongranted_date,
        max(dissident_group_ownership_percent_at_announcement)
            AS dissident_group_ownership_percent_at_announcement,
        max(dissident_group_ownership_percent) AS dissident_group_ownership_percent,
        bool_or(classified_board) AS classified_board,
        max(end_date) AS end_date,
        array_agg(DISTINCT meeting_date) AS meeting_dates,
        min(date_original_13d_filed) AS date_original_13d_filed,
        array_agg(DISTINCT activism_type) AS activism_types,
        max(DISTINCT dissident_board_seats_won) AS dissident_board_seats_won,
        max(dissident_board_seats_sought) AS dissident_board_seats_sought,
        max(market_capitalization_at_time_of_campaign)
            AS market_capitalization_at_time_of_campaign,
        array_agg(DISTINCT campaign_status) AS campaign_status,
        array_remove(array_cat(array_agg(primary_campaign_type),
                  array_agg(secondary_campaign_type)), NULL) AS campaign_types,
        array_agg(DISTINCT holder_type) AS holder_types,
        array_agg(DISTINCT company_name) AS company_names,
        array_agg(DISTINCT country) AS countries,
        array_agg(DISTINCT state_of_headquarters) AS states_of_headquarters,
        array_agg(DISTINCT stock_exchange_primary) AS stock_exchanges ,
        array_agg(DISTINCT factset_industry) AS factset_industries,
        array_agg(DISTINCT primary_sic_code) AS primary_sic_codes,
        TRUE AS activism
     FROM sharkwatch_raw
    GROUP BY cusip_9_digit, eff_announce_date, dissident_group, dissidents),

permnos AS (
    SELECT DISTINCT cusip, permno, permco
    FROM activist_director.permnos AS a
    INNER JOIN crsp.stocknames AS b
    USING (permno)),

sharkwatch AS (
    SELECT *
    FROM sharkwatch_agg AS a
    LEFT JOIN permnos AS b
    ON substr(a.cusip_9_digit, 1, 8)=b.cusip),

activist_director AS (
    SELECT campaign_id,
        min(appointment_date) AS first_appointment_date,
        count(appointment_date) AS num_activist_directors,
        sum(activist_affiliate::integer) AS num_affiliate_directors,
        sum(activist_affiliate IS FALSE::integer) AS num_unaffiliate_directors
    FROM activist_director.activist_directors
    GROUP BY campaign_id),

matched AS (
    SELECT DISTINCT a.*, first_appointment_date,
        num_activist_directors, num_affiliate_directors, num_unaffiliate_directors,
        b.campaign_id IS NOT NULL AS activist_director,
        CASE WHEN b.campaign_id IS NOT NULL THEN
        proxy_fight_went_the_distance ='Yes' END AS elected
    FROM sharkwatch AS a
    LEFT JOIN activist_director AS b
    ON b.campaign_id=ANY(a.campaign_ids)),

delist AS (
    SELECT DISTINCT permno,
        CASE WHEN dlstcd > 100 THEN dlstdt END AS dlstdt,
        CASE WHEN dlstcd > 100 THEN dlstcd END AS dlstcd
    FROM crsp.msedelist),

penultimate AS (
    SELECT DISTINCT a.*, dlstdt, dlstcd
    FROM matched AS a
    LEFT JOIN delist AS c
    USING (permno)
    --  WHERE dlstdt IS NULL OR first_appointment_date < dlstdt
    WHERE (first_date < dlstdt OR dlstdt IS NULL)),
    -- SS: Removing non-listed companies
    --  AND (num_activist_directors!= 9 OR num_activist_directors IS NULL))

first_board_demand_date AS (
    SELECT DISTINCT campaign_ids, min(demand_date) AS first_board_demand_date
    FROM sharkwatch_agg AS a
    INNER JOIN activist_director.key_dates AS b
    ON b.campaign_id=ANY(a.campaign_ids)
    WHERE 'board' = ANY(demand_types)
    GROUP BY a.campaign_ids)

SELECT DISTINCT a.campaign_ids[1] AS campaign_id, a.*,
    b.first_board_demand_date,
    CASE
        WHEN activist_demand_old THEN TRUE
        WHEN first_board_demand_date IS NOT NULL THEN TRUE
    END AS activist_demand,
	CASE
	    WHEN activist_director THEN 'activist_director'
	    WHEN activist_demand_old THEN 'activist_demand'
        WHEN first_board_demand_date IS NOT NULL THEN 'activist_demand'
	    WHEN activism THEN 'activism'
	    ELSE '_none'
	END AS category,
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
    eff_announce_date AS event_date,
    CASE
    	WHEN first_appointment_date - eff_announce_date <= 180 THEN 'early'
    	WHEN first_appointment_date - eff_announce_date > 180 THEN 'late'
    	WHEN activist_demand_old THEN 'activist_demand'
        WHEN first_board_demand_date IS NOT NULL THEN 'activist_demand'
    	WHEN a.activism THEN 'activism'
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
    CASE
        WHEN dlstcd BETWEEN 200 AND 399 AND dlstdt <= eff_announce_date + interval '1 year' THEN 'merged'
        WHEN dlstcd BETWEEN 400 AND 599 AND dlstdt <= eff_announce_date + interval '1 year' THEN 'dropped'
        ELSE 'active' END AS delisted_p1,
    CASE
        WHEN dlstcd BETWEEN 200 AND 399 AND dlstdt <= eff_announce_date + interval '2 years' THEN 'merged'
        WHEN dlstcd BETWEEN 400 AND 599 AND dlstdt <= eff_announce_date + interval '2 years' THEN 'dropped'
        ELSE 'active' END AS delisted_p2,
    CASE
        WHEN dlstcd BETWEEN 200 AND 399 AND dlstdt <= eff_announce_date + interval '3 years' THEN 'merged'
        WHEN dlstcd BETWEEN 400 AND 599 AND dlstdt <= eff_announce_date + interval '3 years' THEN 'dropped'
        ELSE 'active' END AS delisted_p3,
    market_capitalization_at_time_of_campaign *
        dissident_group_ownership_percent_at_announcement/100 AS inv_value
FROM penultimate AS a
LEFT JOIN first_board_demand_date AS b
USING (campaign_ids)
WHERE eff_announce_date < dlstdt OR dlstdt IS NULL;

ALTER TABLE activist_director.activism_events OWNER TO activism;
