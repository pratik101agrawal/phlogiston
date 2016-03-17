CREATE OR REPLACE FUNCTION wipe_reporting(
       source_param varchar(6)
) RETURNS void AS $$
BEGIN
    DELETE FROM task_history_recat
     WHERE source = source_param;

    DELETE FROM tall_backlog
     WHERE source = source_param;

    DELETE FROM category_list
     WHERE source = source_param;

    DELETE FROM recently_closed
     WHERE source = source_param;

    DELETE FROM recently_closed_task
     WHERE source = source_param;

    DELETE FROM maintenance_week
     WHERE source = source_param;

    DELETE FROM maintenance_delta
     WHERE source = source_param;

    DELETE FROM velocity
     WHERE source = source_param;

    DELETE FROM open_backlog_size
     WHERE source = source_param;

END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION find_recently_closed(
    source_prefix varchar(6)
    ) RETURNS void AS $$
DECLARE
  weekrow record;
BEGIN

    DELETE FROM recently_closed
     WHERE source = source_prefix;

    FOR weekrow IN SELECT DISTINCT date
                     FROM task_history_recat
                    WHERE EXTRACT(epoch FROM age(date - INTERVAL '1 day'))/604800 = ROUND(
                          EXTRACT(epoch FROM age(date - INTERVAL '1 day'))/604800)
                      AND source = source_prefix
                    ORDER BY date
    LOOP

        INSERT INTO recently_closed (
            SELECT source_prefix as source,
                   date,
                   category,
                   sum(points) AS points,
                   count(title) as count
              FROM task_history_recat
             WHERE status = '"resolved"'
               AND date = weekrow.date
               AND source = source_prefix
               AND id NOT IN (SELECT id
                                FROM task_history
                               WHERE status = '"resolved"'
                                 AND source = source_prefix
                                 AND date = weekrow.date - interval '1 week' )
             GROUP BY date, category
             );
    END LOOP;

    RETURN;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION find_recently_closed_task(
    source_prefix varchar(6)
    ) RETURNS void AS $$
DECLARE
  daterow record;
BEGIN

    DELETE FROM recently_closed_task
     WHERE source = source_prefix;

    FOR daterow IN SELECT DISTINCT date
                     FROM task_history_recat
                    WHERE source = source_prefix
                      AND date > now() - interval '14 days'
                    ORDER BY date
    LOOP

        INSERT INTO recently_closed_task (
             SELECT source_prefix as source,
                    date,
		    id,
		    title,
                    category
              FROM task_history_recat
             WHERE status = '"resolved"'
               AND date = daterow.date
               AND source = source_prefix
               AND id NOT IN (SELECT id
                                FROM task_history
                               WHERE status = '"resolved"'
                                 AND source = source_prefix
                                 AND date = daterow.date - interval '1 day' )
             );
    END LOOP;

    RETURN;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION backlog_query (
       source_prefix varchar(6),
       status_input text,
       zoom_input boolean
) RETURNS TABLE(date timestamp, category text, sort_order int, points numeric, count numeric) AS $$
BEGIN
        RETURN QUERY
        SELECT t.date,
               t.category,
               MAX(z.sort_order) as sort_order,
               SUM(t.points)::numeric as points,
               SUM(t.count)::numeric as count
          FROM tall_backlog t, category_list z
         WHERE t.source = source_prefix
           AND z.source = source_prefix
           AND t.source = z.source
           AND t.category = z.category
           AND t.status = status_input
           AND (z.zoom = True OR z.zoom = zoom_input)
         GROUP BY t.date, t.category
         ORDER BY t.date, sort_order;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION calculate_velocities(
    source_prefix varchar(6)
    ) RETURNS void AS $$
DECLARE
  weekrow record;
  tranche record;
  min_points_vel float;
  avg_points_vel float;
  max_points_vel float;
  min_count_vel float;
  avg_count_vel float;
  max_count_vel float;
  min_points_grow float;
  avg_points_grow float;
  max_points_grow float;
  min_count_grow float;
  avg_count_grow float;
  max_count_grow float;
BEGIN

    DELETE FROM velocity where source = source_prefix;

    -- Select dates every one week
    INSERT INTO velocity (
    SELECT source,
           category,
           date,
           SUM(points) AS points_resolved,
           SUM(count) AS count_resolved
      FROM tall_backlog
     WHERE status = '"resolved"'
       AND EXTRACT(epoch FROM age(date - INTERVAL '1 day'))/604800 = ROUND(
           EXTRACT(epoch FROM age(date - INTERVAL '1 day'))/604800)
       AND date >= current_date - interval '6 months'
       AND source = source_prefix
     GROUP BY date, source, category);

    UPDATE velocity v
       SET points_open = sum_points_open,
           count_open = sum_count_open
      FROM (SELECT source,
                   date,
                   category,
                   SUM(points) AS sum_points_open,
                   SUM(count) AS sum_count_open
              FROM tall_backlog
             WHERE status = '"open"'
               AND source = source_prefix
             GROUP BY source, date, category) as t
     WHERE t.date = v.date
       AND t.category = v.category
       AND t.source = v.source
       AND v.source = source_prefix;

    UPDATE velocity
       SET delta_resolved_points = COALESCE(subq.delta_resolved_points,0),
           delta_resolved_count = COALESCE(subq.delta_resolved_count,0),
           delta_total_points = COALESCE(subq.delta_total_points,0),
           delta_total_count = COALESCE(subq.delta_total_count,0)
      FROM (SELECT source,
                   date,
                   category,
                   count_resolved - lag(count_resolved) OVER (PARTITION BY source, category ORDER BY date) as delta_resolved_count,
                   points_resolved - lag(points_resolved) OVER (PARTITION BY source, category ORDER BY date) as delta_resolved_points,
                   (count_resolved + count_open) - lag(count_resolved + count_open) OVER (PARTITION BY source, category ORDER BY date) as delta_total_count,
                   (points_resolved + points_open) - lag(points_resolved + points_open) OVER (PARTITION BY source, category ORDER BY date) as delta_total_points
      FROM velocity
     WHERE source = source_prefix) as subq
     WHERE velocity.source = subq.source
       AND velocity.date = subq.date
       AND velocity.category = subq.category;   


FOR weekrow IN SELECT DISTINCT date
                 FROM velocity
                WHERE source = source_prefix
                ORDER BY date
    LOOP
        FOR tranche IN SELECT DISTINCT category
	                 FROM tall_backlog
			WHERE date = weekrow.date
			  AND source = source_prefix
			ORDER BY category
	LOOP
	    SELECT SUM(delta_resolved_points)/3
              INTO min_points_vel
              FROM (SELECT CASE WHEN delta_resolved_points < 0 THEN 0
	                   ELSE delta_resolved_points
			   END
                      FROM velocity subqv
                     WHERE subqv.date >= weekrow.date - interval '3 months'
                       AND subqv.date < weekrow.date
                       AND subqv.source = source_prefix
                       AND subqv.category = tranche.category
                     ORDER BY subqv.delta_resolved_points 
                     LIMIT 3) as x;

	    SELECT SUM(delta_resolved_points)/3
              INTO max_points_vel
              FROM (SELECT delta_resolved_points
                      FROM velocity subqv
                     WHERE subqv.date >= weekrow.date - interval '3 months'
                       AND subqv.date < weekrow.date
                       AND subqv.source = source_prefix
                       AND subqv.category = tranche.category
                     ORDER BY subqv.delta_resolved_points DESC
                     LIMIT 3) as x;

            SELECT AVG(delta_resolved_points)
              INTO avg_points_vel
              FROM velocity subqv
             WHERE subqv.date >= weekrow.date - interval '3 months'
               AND subqv.date < weekrow.date
               AND subqv.source = source_prefix
               AND subqv.category = tranche.category;

	    SELECT SUM(delta_total_points)/3
              INTO min_points_grow
              FROM (SELECT CASE WHEN delta_resolved_points < 0 THEN 0
	                   ELSE delta_resolved_points
			   END
                      FROM velocity subqv
                     WHERE subqv.date >= weekrow.date - interval '3 months'
                       AND subqv.date < weekrow.date
                       AND subqv.source = source_prefix
                       AND subqv.category = tranche.category
                     ORDER BY subqv.delta_resolved_points 
                     LIMIT 3) as x;


            SELECT SUM(delta_resolved_count)/3 AS min_count_vel
              INTO min_count_vel
              FROM (SELECT CASE WHEN delta_resolved_count < 0 THEN 0
	                   ELSE delta_resolved_count
			   END
                      FROM velocity subqv
                     WHERE subqv.date >= weekrow.date - interval '3 months'
                       AND subqv.date < weekrow.date
                       AND subqv.source = source_prefix
                       AND subqv.category = tranche.category
                     ORDER BY subqv.delta_resolved_count 
                     LIMIT 3) as x;

	    SELECT SUM(delta_resolved_count)/3 AS max_count_vel
              INTO max_count_vel
              FROM (SELECT delta_resolved_count
                      FROM velocity subqv
                     WHERE subqv.date >= weekrow.date - interval '3 months'
                       AND subqv.date < weekrow.date
                       AND subqv.source = source_prefix
                       AND subqv.category = tranche.category
                     ORDER BY subqv.delta_resolved_count DESC
                     LIMIT 3) as x;

            SELECT AVG(delta_resolved_count)
              INTO avg_count_vel
              FROM velocity subqv
             WHERE subqv.date >= weekrow.date - interval '3 months'
               AND subqv.date < weekrow.date
               AND subqv.source = source_prefix
               AND subqv.category = tranche.category;

            UPDATE velocity
               SET pes_points_vel = round(min_points_vel),
                   nom_points_vel = round(avg_points_vel),
                   opt_points_vel = round(max_points_vel),
                   pes_count_vel = round(min_count_vel),
                   nom_count_vel = round(avg_count_vel),
                   opt_count_vel = round(max_count_vel)
             WHERE source = source_prefix
               AND category = tranche.category
               AND date = weekrow.date;
        END LOOP;
    END LOOP;

    UPDATE velocity
       SET pes_points_fore = round(points_open::float / GREATEST(pes_points_vel,1)),
           nom_points_fore = round(points_open::float / GREATEST(nom_points_vel,1)),
           opt_points_fore = round(points_open::float / GREATEST(opt_points_vel,1)),
           pes_count_fore = round(count_open::float / GREATEST(pes_count_vel,1)),
           nom_count_fore = round(count_open::float / GREATEST(nom_count_vel,1)),
           opt_count_fore = round(count_open::float / GREATEST(opt_count_vel,1))
     WHERE source = source_prefix;

    UPDATE velocity
       SET pes_points_date = date_trunc('day', date + (pes_points_fore * interval '1 week')),
           nom_points_date = date_trunc('day', date + (nom_points_fore * interval '1 week')),
           opt_points_date = date_trunc('day', date + (opt_points_fore * interval '1 week')),
           pes_count_date = date_trunc('day', date + (pes_count_fore * interval '1 week')),
           nom_count_date = date_trunc('day', date + (nom_count_fore * interval '1 week')),
           opt_count_date = date_trunc('day', date + (opt_count_fore * interval '1 week'))
     WHERE source = source_prefix;

    RETURN;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION set_category_retroactive(
    source_prefix varchar(6)
    ) RETURNS void AS $$
BEGIN

    UPDATE task_history_recat t
       SET category = t0.category
      FROM task_history_recat t0
     WHERE t0.date = (SELECT MAX(date)
                        FROM task_history_recat
                       WHERE source = source_prefix)
       AND t0.source = source_prefix
       AND t.source = source_prefix
       AND t0.id = t.id;

    RETURN;
END;
$$ LANGUAGE plpgsql;
