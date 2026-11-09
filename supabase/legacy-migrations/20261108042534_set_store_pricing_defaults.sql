do $migration$
begin
  update public.pricing_settings
     set usdt_cup_rate = 1160.00,
         mobile_credit_units = 360,
         mobile_cost_cup = 1800.00,
         markup_percent = 35.00,
         rounding_cup = 10,
         updated_at = now()
   where id = 1
     and (
       usdt_cup_rate is distinct from 1160.00
       or mobile_credit_units is distinct from 360
       or mobile_cost_cup is distinct from 1800.00
       or markup_percent is distinct from 35.00
       or rounding_cup is distinct from 10
     );
end;
$migration$;