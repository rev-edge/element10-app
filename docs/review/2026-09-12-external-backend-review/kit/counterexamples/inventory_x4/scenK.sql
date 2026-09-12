\set ON_ERROR_STOP 0
\set ON_ERROR_ROLLBACK on
begin;
\i prelude.sql
select set_config('request.jwt.claims','{"sub":"a4000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
-- K1: direct ledger writes by an authenticated member (movements table grants insert/update/delete)
insert into public.e10_inventory_movements(workspace_id,item_id,movement_type,on_hand_delta,reserved_delta,idempotency_key,organization_id)
 values('shared','rv-item-1','manual_increase',5,0,'rvK-direct','e1000000-0000-4000-8000-0000000000a6');
update public.e10_inventory_movements set on_hand_delta=0 where item_id='rv-item-1';
delete from public.e10_inventory_movements where item_id='rv-item-1';
reset role;
select 'movements for rv-item-1' tag, count(*) from public.e10_inventory_movements where item_id='rv-item-1';
rollback;
