-- Schema-review checkpoint 5: make the legacy checklist count cache transactional.

update public.e10_checklists c set card_count=x.card_count,updated_at=clock_timestamp()
from(select checklist_id,count(*)::integer card_count from public.e10_cards group by checklist_id)x
where c.id=x.checklist_id and c.card_count<>x.card_count;
update public.e10_checklists c set card_count=0,updated_at=clock_timestamp()
where c.card_count<>0 and not exists(select 1 from public.e10_cards where checklist_id=c.id);
alter table public.e10_checklists add constraint e10_checklists_card_count_nonnegative check(card_count>=0)not valid;
alter table public.e10_checklists validate constraint e10_checklists_card_count_nonnegative;

create function e10.maintain_checklist_card_count_insert()returns trigger
language plpgsql security definer set search_path=public as $$
begin
 perform set_config('e10.card_count_maintenance','on',true);
 update public.e10_checklists c set card_count=c.card_count+x.n,updated_at=clock_timestamp()
 from(select checklist_id,count(*)::integer n from new_cards group by checklist_id)x where c.id=x.checklist_id;
 perform set_config('e10.card_count_maintenance','off',true);
 return null;
end$$;
create function e10.maintain_checklist_card_count_delete()returns trigger
language plpgsql security definer set search_path=public as $$
begin
 perform set_config('e10.card_count_maintenance','on',true);
 update public.e10_checklists c set card_count=c.card_count-x.n,updated_at=clock_timestamp()
 from(select checklist_id,count(*)::integer n from old_cards group by checklist_id)x where c.id=x.checklist_id;
 perform set_config('e10.card_count_maintenance','off',true);
 return null;
end$$;
create function e10.maintain_checklist_card_count_move()returns trigger
language plpgsql security definer set search_path=public as $$
begin
 perform set_config('e10.card_count_maintenance','on',true);
 update public.e10_checklists c set card_count=c.card_count+x.delta,updated_at=clock_timestamp()
 from(
  select checklist_id,sum(delta)::integer delta from(
   select checklist_id,-count(*)::bigint delta from old_cards group by checklist_id
   union all select checklist_id,count(*)::bigint from new_cards group by checklist_id
  )d group by checklist_id having sum(delta)<>0
 )x where c.id=x.checklist_id;
 perform set_config('e10.card_count_maintenance','off',true);
 return null;
end$$;
revoke all on function e10.maintain_checklist_card_count_insert(),e10.maintain_checklist_card_count_delete(),e10.maintain_checklist_card_count_move()from public,anon,authenticated;
grant execute on function e10.maintain_checklist_card_count_insert(),e10.maintain_checklist_card_count_delete(),e10.maintain_checklist_card_count_move()to service_role;
create trigger e10_cards_count_insert after insert on public.e10_cards referencing new table as new_cards for each statement execute function e10.maintain_checklist_card_count_insert();
create trigger e10_cards_count_delete after delete on public.e10_cards referencing old table as old_cards for each statement execute function e10.maintain_checklist_card_count_delete();
create trigger e10_cards_count_move after update on public.e10_cards referencing old table as old_cards new table as new_cards for each statement execute function e10.maintain_checklist_card_count_move();

create function e10.guard_checklist_card_count()returns trigger language plpgsql security definer set search_path=public as $$
declare actual integer;
begin
 if current_setting('e10.card_count_maintenance',true)='on'then return new;end if;
 if tg_op='UPDATE'and new.card_count=old.card_count then return new;end if;
 select count(*)::integer into actual from public.e10_cards where checklist_id=new.id;
 if new.card_count<>actual then raise exception using errcode='23514',message='checklist_card_count_is_maintained';end if;
 return new;
end$$;
revoke all on function e10.guard_checklist_card_count()from public,anon,authenticated;grant execute on function e10.guard_checklist_card_count()to service_role;
create trigger e10_checklist_card_count_guard before insert or update on public.e10_checklists for each row execute function e10.guard_checklist_card_count();

comment on column public.e10_checklists.card_count is'Transactionally maintained cache of current e10_cards rows. Statement-level delta triggers serialize concurrent updates on the checklist row.';
