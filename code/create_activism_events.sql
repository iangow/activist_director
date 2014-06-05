DROP TABLE IF EXISTS activist_director.activism_events CASCADE;

CREATE TABLE activist_director.activism_events AS
WITH sharkwatch AS (
    SELECT DISTINCT permno, cusip_9_digit, announce_date,
        least(announce_date, date_original_13d_filed) AS eff_announce_date,
        dissident_group,
        company_name, country, state_of_headquarters,
        stock_exchange_primary, factset_industry, primary_sic_code,
        market_capitalization_at_time_of_campaign, classified_board,
        array_remove(regexp_split_to_array(
        regexp_replace(dissident_group_with_sharkwatch50, 'Dissident Group: ', '', 'g'),
        '\s+SharkWatch50\?:\s+(Yes|No)'),'') AS dissidents,
        activism_type, primary_campaign_type, secondary_campaign_type, dissident_board_seats_sought,
        dissident_board_seats_won,
        campaign_resulted_in_board_seats_for_activist, campaign_status,
        s13d_filer, dissident_group_includes_sharkwatch50_member AS sharkwatch50,
        holder_type,
        dissident_group_ownership_percent,
        dissident_group_ownership_percent_at_announcement,
        date_original_13d_filed, proxy_fight_announce_date,
        meeting_date, dissident_board_seats_wongranted_date,
        end_date,
        LEAST(proxy_fight_announce_date, announce_date) AS first_date,
        GREATEST(meeting_date, end_date) AS last_date,
        proxy_fight='Yes' AS proxy_fight, proxy_fight_went_definitive,
        proxy_fight_went_the_distance,
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
        dissident_board_seats_wongranted_date IS NOT NULL AS activist_demand_old,
        TRUE AS activism
    FROM factset.sharkwatch AS a
    INNER JOIN activist_director.permnos AS b
    ON substr(a.cusip_9_digit,1,8) = b.ncusip
    WHERE country='United States'
        AND state_of_incorporation != 'Non-U.S.'
        AND factset_industry != 'Investment Trusts/Mutual Funds'
        AND (s13d_filer='Yes' OR proxy_fight='Yes' OR
        holder_type IN ('Hedge Fund Company', 'Investment Adviser'))
        AND holder_type NOT IN ('Corporation')
        AND campaign_status='Closed'
        AND least(announce_date, date_original_13d_filed) >= '2004-01-01'
        AND least(announce_date, date_original_13d_filed) <= '2012-12-31'
        AND activism_type != '13D Filer - No Publicly Disclosed Activism'
    ORDER BY permno, first_date),

activist_director AS (
    SELECT permno, announce_date, dissident_group,
        min(appointment_date) AS first_appointment_date,
        count(appointment_date) AS num_activist_directors,
        sum(activist_affiliate::INT) AS num_affiliate_directors,
        sum(activist_affiliate IS FALSE::INT) AS num_unaffiliate_directors
    FROM activist_director.activist_director_matched
    GROUP BY permno, announce_date, dissident_group),

matched AS (
    SELECT DISTINCT a.*, first_appointment_date,
        num_activist_directors, num_affiliate_directors, num_unaffiliate_directors,
        b.permno IS NOT NULL AS activist_director,
        CASE WHEN b.permno IS NOT NULL THEN
        proxy_fight_went_the_distance ='Yes' END AS elected
    FROM sharkwatch AS a
    LEFT JOIN activist_director AS b
    ON a.permno=b.permno AND a.announce_date=b.announce_date
    AND a.dissident_group=b.dissident_group),

delist AS (
    SELECT DISTINCT permno,
        CASE WHEN dlstcd > 100 THEN dlstdt END AS dlstdt,
        CASE WHEN dlstcd > 100 THEN dlstcd END AS dlstcd
    FROM crsp.msedelist),

penultimate AS (
    SELECT DISTINCT a.*, dlstdt, dlstcd
    FROM matched AS a
    INNER JOIN delist AS c
    USING (permno)
    --  WHERE dlstdt IS NULL OR first_appointment_date < dlstdt
    WHERE (announce_date < dlstdt OR dlstdt IS NULL)),
    -- SS: Removing non-listed companies
    --  AND (num_activist_directors!= 9 OR num_activist_directors IS NULL))

first_board_demand_date AS (
    SELECT DISTINCT cusip_9_digit, announce_date, dissident_group, min(event_date) AS first_board_demand_date
    FROM activist_director.key_dates_all
    WHERE board_demand
    GROUP BY cusip_9_digit, announce_date, dissident_group)

SELECT DISTINCT a.*,
    b.first_board_demand_date,
    CASE WHEN activist_demand_old THEN TRUE WHEN first_board_demand_date IS NOT NULL THEN TRUE END AS activist_demand,
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
    --    elected,
    --  CASE WHEN activist_director THEN first_appointment_date END AS
    first_appointment_date,
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
        dissident_group_ownership_percent_at_announcement/100 AS inv_value --,
    -- CASE WHEN activist_director IS TRUE THEN TRUE ELSE FALSE END AS
    -- activist_director --,
    -- NOT activist_director AND activist_demand AS activist_demand,
    -- NOT activist_demand AND activism AS activism
FROM penultimate AS a
LEFT JOIN first_board_demand_date AS b
ON a.cusip_9_digit=b.cusip_9_digit AND eff_announce_date=b.announce_date AND a.dissident_group=b.dissident_group
WHERE eff_announce_date < dlstdt OR dlstdt IS NULL
ORDER BY permno, announce_date;

ALTER TABLE activist_director.activism_events OWNER TO activism;
