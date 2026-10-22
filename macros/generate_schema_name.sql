{% macro generate_schema_name(custom_schema_name, node) -%}
    {#- Use the custom schema exactly as specified per model config (BRONZE/SILVER/GOLD),
        instead of dbt's default behavior of suffixing it onto the target schema. -#}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
