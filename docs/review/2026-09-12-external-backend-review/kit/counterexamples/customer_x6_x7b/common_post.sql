-- helper: create+approve+post a single-line USD retail transaction for customer k with gross g at date d, location lk (nullable key), channel ch
create function pg_temp.post_tx(k text, cust text, g numeric, d timestamptz, lk text, ch text) returns uuid language plpgsql as $$
declare d_id uuid; tx uuid; loc uuid; line jsonb;
begin
  loc:=case when lk is null then null else pg_temp.i(lk) end;
  line:=jsonb_build_object('purchase_kind','retail','capture_source','manual','source_line_id',k||'-line','quantity',1,'merchandise_gross',g,'merchandise_discount',0,'sales_channel',ch);
  if loc is not null then line:=line||jsonb_build_object('location_id',loc); end if;
  d_id:=(public.e10_org_create_customer_transaction_draft(pg_temp.i('org'),pg_temp.i(cust),'USD',d,'exact','fixture '||k,jsonb_build_array(line),k||'-draft')->>'draft_id')::uuid;
  perform public.e10_org_approve_customer_transaction_draft(pg_temp.i('org'),d_id,1,k||'-approve');
  tx:=(public.e10_org_post_customer_transaction_draft(pg_temp.i('org'),d_id,1,k||'-post')->>'transaction_id')::uuid;
  perform pg_temp.remember(k,tx);
  return tx;
end $$;
grant execute on function pg_temp.post_tx(text,text,numeric,timestamptz,text,text) to authenticated, anon, public;
