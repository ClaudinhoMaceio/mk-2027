-- MK Audiovisual | Supabase SQL
-- Execute este arquivo no SQL Editor do seu projeto Supabase.
create extension if not exists pgcrypto;

create table if not exists public.contracts (
 id uuid primary key default gen_random_uuid(),
 public_token uuid not null unique default gen_random_uuid(),
 client_name text not null,
 cpf text not null,
 phone text not null,
 email text,
 address text,
 event_date date not null,
 start_time time,
 end_time time,
 venue text not null,
 payment_terms text,
 items jsonb not null default '[]'::jsonb,
 total numeric(12,2) not null default 0,
 notes text,
 status text not null default 'pending' check (status in ('pending','signed','cancelled')),
 signature_name text,
 signature_data text,
 signed_at timestamptz,
 signer_user_agent text,
 created_at timestamptz not null default now()
);

alter table public.contracts enable row level security;

-- Somente usuários autenticados podem ler e administrar a tabela.
drop policy if exists "admin read contracts" on public.contracts;
create policy "admin read contracts" on public.contracts for select to authenticated using (true);
drop policy if exists "admin insert contracts" on public.contracts;
create policy "admin insert contracts" on public.contracts for insert to authenticated with check (true);
drop policy if exists "admin update contracts" on public.contracts;
create policy "admin update contracts" on public.contracts for update to authenticated using (true) with check (true);
drop policy if exists "admin delete contracts" on public.contracts;
create policy "admin delete contracts" on public.contracts for delete to authenticated using (true);

-- RPC pública: devolve apenas o contrato cujo token aleatório foi apresentado.
create or replace function public.get_contract_by_token(p_token uuid)
returns jsonb
language sql
security definer
set search_path = public
as $$
 select jsonb_build_object(
  'id',id,'public_token',public_token,'client_name',client_name,'cpf',cpf,
  'phone',phone,'email',email,'address',address,'event_date',event_date,
  'start_time',start_time,'end_time',end_time,'venue',venue,
  'payment_terms',payment_terms,'items',items,'total',total,'notes',notes,
  'status',status,'signature_name',signature_name,'signature_data',signature_data,
  'signed_at',signed_at,'created_at',created_at
 ) from public.contracts where public_token=p_token limit 1;
$$;

-- Assinatura vinculada ao token. O contrato só pode ser assinado uma vez.
create or replace function public.sign_contract_by_token(
 p_token uuid, p_name text, p_signature text, p_user_agent text
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
 if length(trim(coalesce(p_name,''))) < 3 then raise exception 'Nome de assinatura inválido'; end if;
 if length(coalesce(p_signature,'')) < 100 then raise exception 'Assinatura não informada'; end if;
 update public.contracts
 set status='signed', signature_name=trim(p_name), signature_data=p_signature,
     signed_at=now(), signer_user_agent=left(coalesce(p_user_agent,''),1000)
 where public_token=p_token and status='pending';
 if not found then raise exception 'Contrato não encontrado ou já assinado'; end if;
 return true;
end;
$$;

revoke all on function public.get_contract_by_token(uuid) from public;
grant execute on function public.get_contract_by_token(uuid) to anon, authenticated;
revoke all on function public.sign_contract_by_token(uuid,text,text,text) from public;
grant execute on function public.sign_contract_by_token(uuid,text,text,text) to anon, authenticated;

-- Não conceda SELECT/INSERT/UPDATE anônimo diretamente na tabela.
-- Para produção: restrinja quem pode criar usuários no Supabase Auth e habilite MFA para administradores.
