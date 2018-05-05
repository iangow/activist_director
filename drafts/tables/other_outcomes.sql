WITH compustat AS (
    SELECT a.gvkey, a.datadate,
        sale, at, CASE WHEN at > 0 THEN log(at) END AS log_at,
        ceq, che, ni, ib, oibdp, oiadp,
        COALESCE(dp,0) AS dp,
        COALESCE(dlc,0) AS dlc,
        COALESCE(dltt,0) AS dltt,
        COALESCE(xrd,0) AS xrd,
        COALESCE(xad,0) AS xad,
        COALESCE(capx, 0) AS capx,
        COALESCE(gdwl, 0) AS gdwl,
        COALESCE(dvc, 0) AS dvc,
        COALESCE(dvp, 0) AS dvp,
        COALESCE(prstkc,0) AS prstkc,
        COALESCE(pstkrv,0) AS pstkrv,
        COALESCE(acdo,0) AS acdo,
        COALESCE(aldo,0) AS aldo,
        COALESCE(sppe,0) AS sppe,
        COALESCE(do_,0) AS do_,
        COALESCE(COALESCE(acdo,0) + COALESCE(aldo,0),sppe, do_,0) AS disc_oper,
        siv, ivao + ivaeq AS iva, ppent, sret,
        CASE
            WHEN txfed IS NOT NULL THEN txfed + COALESCE(txs,0)
            WHEN txfo IS NOT NULL AND txt-txdi IS NOT NULL THEN txt-txdi-txfo
            END AS txfed,
        CASE
            WHEN txfo IS NOT NULL THEN txfo
            WHEN txfed = txt-txdi THEN 0
            WHEN pidom = pi THEN 0
            ELSE txt-txdi-txfo
        END AS txfo,
        COALESCE(txt-txdi, txfed + COALESCE(txs,0) + txfo) AS txww,
        COALESCE(pifo, pi - pidom) AS pifo,
        COALESCE(pidom, pi - pifo) AS pidom,
        COALESCE(pi, pidom + pifo) AS pi
    FROM comp.funda AS a
    WHERE indfmt='INDL' AND consol='C' AND popsrc='D' AND datafmt='STD'),

compustat_w_lags AS (
    SELECT gvkey, datadate, at, che, dvc, prstkc, pstkrv, oibdp,
        dltt, dlc, ceq, xrd, xad, capx,
        lag(at, 1) OVER w AS at_m1,
        lead(at, 1) OVER w AS at_p1,
        lead(che, 1) OVER w AS che_p1,
        lead(ceq, 1) OVER w AS ceq_p1,
        lead(dlc, 1) OVER w AS dlc_p1,
        lead(dltt, 1) OVER w AS dltt_p1,
        sum(oibdp) OVER p1 AS oibdp_cum_p1,
        sum(coalesce(dvc,0)) OVER p1 AS dvc_cum_p1,
        sum(coalesce(prstkc,0)) OVER p1 AS prstkc_cum_p1,
        sum(coalesce(pstkrv,0)) OVER p1 AS pstkrv_cum_p1,
        sum(xrd) OVER p1 AS xrd_cum_p1,
        sum(xad) OVER p1 AS xad_cum_p1,
        sum(capx) OVER p1 AS capx_cum_p1,
        lead(at, 2) OVER w AS at_p2,
        lead(che, 2) OVER w AS che_p2,
        lead(ceq, 2) OVER w AS ceq_p2,
        lead(dlc, 2) OVER w AS dlc_p2,
        lead(dltt, 2) OVER w AS dltt_p2,
        sum(oibdp) OVER p2 AS oibdp_cum_p2,
        sum(coalesce(dvc,0)) OVER p2 AS dvc_cum_p2,
        sum(coalesce(prstkc,0)) OVER p2 AS prstkc_cum_p2,
        sum(coalesce(pstkrv,0)) OVER p2 AS pstkrv_cum_p2,
        sum(xrd) OVER p2 AS xrd_cum_p2,
        sum(xad) OVER p2 AS xad_cum_p2,
        sum(capx) OVER p2 AS capx_cum_p2,
        lead(at, 3) OVER w AS at_p3,
        lead(che, 3) OVER w AS che_p3,
        lead(ceq, 3) OVER w AS ceq_p3,
        lead(dlc, 3) OVER w AS dlc_p3,
        lead(dltt, 3) OVER w AS dltt_p3,
        sum(oibdp) OVER p3 AS oibdp_cum_p3,
        sum(coalesce(dvc,0)) OVER p3 AS dvc_cum_p3,
        sum(coalesce(prstkc,0)) OVER p3 AS prstkc_cum_p3,
        sum(coalesce(pstkrv,0)) OVER p3 AS pstkrv_cum_p3,
        sum(xrd) OVER p3 AS xrd_cum_p3,
        sum(xad) OVER p3 AS xad_cum_p3,
        sum(capx) OVER p3 AS capx_cum_p3,
        lag(datadate) OVER w AS datadate_m1
    FROM compustat
    WINDOW w AS (PARTITION BY gvkey ORDER BY datadate),
        p1 AS (PARTITION BY gvkey ORDER BY datadate
                ROWS BETWEEN 1 FOLLOWING AND 1 FOLLOWING),
        p2 AS (PARTITION BY gvkey ORDER BY datadate
                ROWS BETWEEN 1 FOLLOWING AND 2 FOLLOWING),
        p3 AS (PARTITION BY gvkey ORDER BY datadate
                ROWS BETWEEN 1 FOLLOWING AND 3 FOLLOWING))

SELECT gvkey, datadate,
    CASE WHEN at > 0 THEN xrd/at END AS rnd_cum,
    CASE WHEN at > 0 THEN xad/at END AS adv_cum,
    CASE WHEN at > 0 THEN capx/at END AS capex_cum,

    CASE WHEN at > 0 THEN che_p1/at END AS cash_p1,
    CASE WHEN oibdp_cum_p1 > 0
        THEN (dvc_cum_p1 + prstkc_cum_p1 - pstkrv_cum_p1)/oibdp_cum_p1 END AS payout_p1,
    CASE WHEN dltt_p1 + dlc_p1 + ceq_p1 > 0
        THEN (dltt_p1 + dlc_p1)/(dltt_p1 + dlc_p1 + ceq_p1)
    END AS leverage_p1,
    CASE WHEN at > 0 THEN (xrd_cum_p1)/at END AS rnd_cum_p1,
    CASE WHEN at > 0 THEN (xad_cum_p1)/at END AS adv_cum_p1,
    CASE WHEN at > 0 THEN (capx_cum_p1)/at END AS capex_cum_p1,

    CASE WHEN at > 0 THEN che_p2/at END AS cash_p2,
    CASE WHEN oibdp_cum_p2 > 0
        THEN (dvc_cum_p2 + prstkc_cum_p2 - pstkrv_cum_p2)/oibdp_cum_p2 END AS payout_p2,
    -- CASE WHEN dltt+dlc+ceq > 0 THEN (dltt+dlc)/(dltt+dlc+ceq) END AS lev,
    CASE WHEN dltt_p2 + dlc_p2 + ceq_p2 > 0
        THEN (dltt_p2 + dlc_p2)/(dltt_p2 + dlc_p2 + ceq_p2)
    END AS leverage_p2,
    CASE WHEN at > 0 THEN (xrd_cum_p2)/at END AS rnd_cum_p2,
    CASE WHEN at > 0 THEN (xad_cum_p2)/at END AS adv_cum_p2,
    CASE WHEN at > 0 THEN (capx_cum_p2)/at END AS capex_cum_p2,

    CASE WHEN at > 0 THEN che_p3/at END AS cash_p3,
    CASE WHEN oibdp_cum_p3 > 0
        THEN (dvc_cum_p3 + prstkc_cum_p3 - pstkrv_cum_p3)/oibdp_cum_p3 END AS payout_p3,
    CASE WHEN dltt_p3 + dlc_p3 + ceq_p3 > 0
        THEN (dltt_p3 + dlc_p3)/(dltt_p3 + dlc_p3 + ceq_p3)
    END AS leverage_p3,
    CASE WHEN at > 0 THEN (xrd_cum_p3)/at END AS rnd_cum_p3,
    CASE WHEN at > 0 THEN (xad_cum_p3)/at END AS adv_cum_p3,
    CASE WHEN at > 0 THEN (capx_cum_p3)/at END AS capex_cum_p3
FROM compustat_w_lags
