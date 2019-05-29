/* Add derived measurements to the processed measurements. */

-- join two measurement types to make it easy to derive values from
-- multiple measurements
drop function if exists combine_measures cascade;
CREATE OR REPLACE FUNCTION combine_measures(site_id int, data_source text,
                                            measurement_name1 text,
					    measurement_name2 text)
  RETURNS TABLE (
    measurement_time timestamp,
    value1 numeric,
    value2 numeric,
    flagged1 boolean,
    flagged2 boolean
  ) as $$
  select m1.measurement_time,
	 m1.value,
	 m2.value,
	 coalesce(m1.flagged, false),
	 coalesce(m2.flagged, false)
    from (select *
	    from _processed_measurements
	   where measurement_type_id=get_measurement_id(site_id, data_source, measurement_name1)) m1
	   join
	   (select *
	      from _processed_measurements
	     where measurement_type_id=get_measurement_id(site_id, data_source, measurement_name2)) m2
	       on m1.measurement_time=m2.measurement_time;
$$ language sql;

/* WFMS */
drop view if exists wfms_no2 cascade;
create or replace view wfms_no2 as
  select measurement_type_id,
	 measurement_time,
	 value,
	 flagged or
	   is_outlier(value, runmed(value) over w,
		      runmad(value) over w) as flagged
    from (select get_measurement_id(1, 'derived', 'NO2') as measurement_type_id,
		 measurement_time,
		 (value2 - value1) /
		   interpolate_ce(get_measurement_id(1, 'campbell', 'NOx'),
				  measurement_time) as value,
		 flagged1 or flagged2 as flagged
	    from combine_measures(1, 'campbell', 'NO', 'NOx')) cm1
	   WINDOW w AS (partition by measurement_type_id
			ORDER BY measurement_time
			rows between 120 preceding and 120 following);

drop view if exists wfms_slp cascade;
create or replace view wfms_slp as
  select get_measurement_id(1, 'derived', 'SLP'),
	 measurement_time,
	 value1 *
	   (1 - .0065 * 1483.5 /
	   (value2 + .0065 * 1483.5 + 273.15))^(-5.257) as value,
	 flagged1 or flagged2 as flagged
    from combine_measures(1, 'campbell', 'BP', 'PTemp_C');

drop view if exists wfms_ws cascade;
create or replace view wfms_ws as
  select get_measurement_id(1, 'derived', 'WS'),
	 measurement_time,
	 greatest(case when not flagged1 then value1
		  else null end,
		  case when not flagged2 then value2
		  else null end) as value,
	 flagged1 and flagged2 as flagged
    from combine_measures(1, 'campbell', 'WS3Cup', 'WS3CupB');

-- u and v vector wind speeds
drop view if exists wfms_ws_components cascade;
create or replace view wfms_ws_components as
  with wswd as (select ws1.measurement_time as measurement_time,
		       ws1.value as ws,
		       pi() * (270 - wd1.value) / 180 as theta,
		       ws1.flagged or wd1.flagged as flagged
		  from wfms_ws ws1
  			 join (select *
				 from _processed_measurements
				where measurement_type_id=get_measurement_id(1, 'campbell', 'WindDir_D1_WVT')) wd1
			     on ws1.measurement_time=wd1.measurement_time)
  select get_measurement_id(1, 'derived', 'WS_u'),
	 measurement_time,
	 (ws * sin(theta))::numeric as value,
	 flagged
    from wswd
   union
  select get_measurement_id(1, 'derived', 'WS_v'),
	 measurement_time,
	 (ws * cos(theta))::numeric as value,
	 flagged
    from wswd;

drop view if exists wfms_ws_max cascade;
create or replace view wfms_ws_max as
  select get_measurement_id(1, 'derived', 'WS_Max'),
	 measurement_time,
	 greatest(case when not flagged1 then value1
		  else null end,
		  case when not flagged2 then value2
		  else null end) as value,
	 flagged1 and flagged2 as flagged
    from combine_measures(1, 'campbell', 'WS3Cup_Max', 'WS3CupB_Max');

drop view if exists derived_wfms_measurements cascade;
create or replace view derived_wfms_measurements as
  select * from wfms_no2
   union select * from wfms_slp
   union select * from wfms_ws
   union select * from wfms_ws_max
   union select * from wfms_ws_components;

/* PSP */
drop view if exists psp_no2 cascade;
create or replace view psp_no2 as
  select measurement_type_id,
	 measurement_time,
	 value,
	 flagged or
	   is_outlier(value, runmed(value) over w,
		      runmad(value) over w) as flagged
    from (select get_measurement_id(3, 'derived', 'NO2') as measurement_type_id,
		 measurement_time,
		 (value2 - value1) /
		   interpolate_ce(get_measurement_id(3, 'envidas', 'NOx'),
				  measurement_time) as value,
		 flagged1 or flagged2 as flagged
	    from combine_measures(3, 'envidas', 'NO', 'NOx')) cm1
	   WINDOW w AS (partition by measurement_type_id
			ORDER BY measurement_time
			rows between 120 preceding and 120 following);

drop view if exists psp_hno3 cascade;
create or replace view psp_hno3 as
  select get_measurement_id(3, 'derived', 'HNO3'),
	 measurement_time,
	 value1 - value2 as value,
	 flagged1 or flagged2 as flagged
    from combine_measures(3, 'envidas', 'NOy', 'NOy-HNO3');

drop view if exists psp_precip cascade;
create or replace view psp_precip as
  select get_measurement_id(3, 'derived', 'Precip'),
	 measurement_time,
	 (case when value<=-.02 then value + .5
	  else value end) * 25.4 as value,
	 flagged
    from (select measurement_time,
		 value - lag(value) over w as value,
		 flagged or lag(flagged) over w as flagged
	    from _processed_measurements
	   where measurement_type_id=get_measurement_id(3, 'envidas', 'Rain')
		 WINDOW w AS (partition by measurement_type_id
			      ORDER BY measurement_time)) r1;

drop view if exists psp_teoma25_base cascade;
create or replace view psp_teoma25_base as
  select get_measurement_id(3, 'derived', 'TEOMA(2.5)BaseMC'),
	 measurement_time,
	 value1 + value2 as value,
	 flagged1 or flagged2 as flagged
    from combine_measures(3, 'envidas', 'TEOMA(2.5)MC', 'TEOMA(2.5)RefMC');

drop view if exists psp_teombcrs_base cascade;
create or replace view psp_teombcrs_base as
  select get_measurement_id(3, 'derived', 'TEOMB(crs)BaseMC'),
	 measurement_time,
	 value1 + value2 as value,
	 flagged1 or flagged2 as flagged
    from combine_measures(3, 'envidas', 'TEOMB(crs)MC', 'TEOMB(crs)RefMC');

drop view if exists psp_dichot10_base cascade;
create or replace view psp_dichot10_base as
  select get_measurement_id(3, 'derived', 'Dichot(10)BaseMC'),
	 measurement_time,
	 value1 + value2 as value,
	 flagged1 or flagged2 as flagged
    from combine_measures(3, 'envidas', 'Dichot(10)MC', 'Dichot(10)RefMC');

drop view if exists psp_wood_smoke cascade;
create or replace view psp_wood_smoke as
  select get_measurement_id(3, 'derived', 'Wood smoke'),
	 measurement_time,
	 value1 - value2 as value,
	 flagged1 or flagged2 as flagged
    from combine_measures(3, 'envidas', 'BC1', 'BC6');

drop view if exists psp_ws_components cascade;
create or replace view psp_ws_components as
  with wswd as (select measurement_time,
		       value1 as ws,
		       pi() * (270 - value2) / 180 as theta,
		       flagged1 or flagged2 as flagged
		  from combine_measures(3, 'envidas', 'VWS', 'VWD'))
  select get_measurement_id(3, 'derived', 'WS_u'),
	 measurement_time,
	 (ws * sin(theta))::numeric as value,
	 flagged
    from wswd
   union
  select get_measurement_id(3, 'derived', 'WS_v'),
	 measurement_time,
	 (ws * cos(theta))::numeric as value,
	 flagged
    from wswd;

drop view if exists derived_psp_measurements cascade;
create or replace view derived_psp_measurements as
  select * from psp_no2
   union select * from psp_hno3
   union select * from psp_precip
   union select * from psp_teoma25_base
   union select * from psp_teombcrs_base
   union select * from psp_dichot10_base
   union select * from psp_wood_smoke
   union select * from psp_ws_components;

/* Combine all derived measurements. */
create or replace view derived_measurements as
  select * from derived_wfms_measurements
   union select * from derived_psp_measurements;
