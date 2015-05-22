WITH partial AS (
    SELECT campaign_id,
    regexp_split_to_table(regexp_replace(company_tacticsin_play_defense_changes, E'"', E'\\"', 'g'), E'Date:\\s*') AS items
    FROM factset.sharkwatch_new
    WHERE company_tacticsin_play_defense_changes IS NOT NULL),

processed AS (
    SELECT campaign_id, regexp_replace(items,
                                       E'^(.*?)\s*Type:\s*(.*?)Description:\s*(.*?)Amendments to:\s*(.*)$',
                                       E'{"Date":"\\1", "Type":"\\2", "Description":\"\\3", "Amendments":"\\4"}', 'g') AS items
    FROM partial
    WHERE items !='' AND items IS NOT NULL)

SELECT *
    FROM processed
WHERE items IS NOT NULL AND items !~ '^(null)+$'
