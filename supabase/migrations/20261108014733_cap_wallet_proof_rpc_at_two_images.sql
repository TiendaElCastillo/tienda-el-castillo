do $migration$
declare
  v_definition text;
begin
  select pg_get_functiondef(
    'public.submit_wallet_deposit_proofs(uuid,text[],text,text,text,text)'::regprocedure
  ) into v_definition;

  if position('cardinality(p_proof_paths)>5' in v_definition)=0
     or position('Adjunta entre 1 y 5 comprobantes.' in v_definition)=0 then
    raise exception 'No se reconoce la versión esperada de submit_wallet_deposit_proofs; se cancela la migración sin modificarla.';
  end if;

  v_definition := replace(
    v_definition,
    'cardinality(p_proof_paths)>5',
    'cardinality(p_proof_paths)>2'
  );
  v_definition := replace(
    v_definition,
    'Adjunta entre 1 y 5 comprobantes.',
    'Adjunta entre 1 y 2 comprobantes.'
  );

  execute v_definition;
end;
$migration$;
