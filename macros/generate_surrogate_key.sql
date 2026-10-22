{% macro generate_surrogate_key(column_list) -%}
    {#- Local replacement for dbt_utils.generate_surrogate_key() (SD-17): this account has no
        general internet egress from the interactive dbt execution path used in this build
        (confirmed: hub.getdbt.com unreachable; EXTERNAL_ACCESS_INTEGRATIONS only attaches to
        formally deployed DBT PROJECT objects run via EXECUTE DBT PROJECT, not this workflow).
        Same behavior: MD5 of the pipe-delimited, null-safe concatenation of the given columns. -#}
    md5(concat_ws('|',
        {%- for column in column_list -%}
            coalesce(cast({{ column }} as varchar), '_surrogate_key_null_')
            {%- if not loop.last -%},{%- endif -%}
        {%- endfor -%}
    ))
{%- endmacro %}
