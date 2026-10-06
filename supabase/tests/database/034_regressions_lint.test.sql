-- Regression (db-lint-fails-ci): CI runs `supabase db lint --level warning --fail-on warning`, which runs
-- plpgsql_check_function(oid, format := 'json') on every non-trigger PL/pgSQL function in the user
-- schemas. Any 'error', 'warning' or 'warning extra' fails the step. This test runs the same check so a
-- lint failure is visible in the database test run. Skipped when plpgsql_check is not installed.
select exists (select 1 from pg_catalog.pg_available_extensions where name = 'plpgsql_check') as has_plpgsql_check \gset
begin;
-- plpgsql_check must be loaded before any PL/pgSQL (pgTAP) code runs in the session, otherwise its
-- statement call-stack tracking breaks.
\if :has_plpgsql_check
create extension if not exists plpgsql_check with schema extensions;
\endif
select plan(3);

\if :has_plpgsql_check
create temp table lint_issues as
select n.nspname || '.' || p.proname as function_name,
       r.j ->> 'level' as level,
       r.j ->> 'message' as message,
       coalesce(r.j -> 'statement' ->> 'lineNumber', r.j ->> 'lineNumber') as line_no
  from pg_catalog.pg_namespace n
  join pg_catalog.pg_proc p on p.pronamespace = n.oid
  join pg_catalog.pg_language l on p.prolang = l.oid
 cross join lateral (select plpgsql_check_function(p.oid, format := 'json')::jsonb as doc) c
 cross join lateral jsonb_array_elements(c.doc -> 'issues') r(j)
 where l.lanname = 'plpgsql'
   and p.prorettype <> 'pg_catalog.trigger'::regtype
   and n.nspname in ('public', 'app', 'audit');

select is_empty(
  $$ select function_name || ': ' || message from lint_issues where level like 'error%' order by 1 $$,
  'plpgsql_check reports no errors (supabase db lint)');
select is_empty(
  $$ select function_name || ' line ' || coalesce(line_no, '?') || ': ' || message
       from lint_issues where level like 'warning%' and level <> 'warning extra' order by 1 $$,
  'plpgsql_check reports no warnings (supabase db lint --fail-on warning)');
select is_empty(
  $$ select function_name || ' line ' || coalesce(line_no, '?') || ': ' || message
       from lint_issues where level = 'warning extra' order by 1 $$,
  'plpgsql_check reports no extra warnings (counted as warnings by supabase db lint)');
\else
select skip('plpgsql_check is not installed', 3);
\endif

select * from finish();
rollback;
