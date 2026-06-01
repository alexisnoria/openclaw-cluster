# tests/bats/README.md

Esta carpeta contiene los **tests unitarios** del proyecto, escritos con [bats](https://github.com/bats-core/bats-core).

## Estructura

```
tests/
├── bats/
│   ├── helpers/
│   │   └── load.bash         # sourcea lib/cluster.sh y define aserciones
│   ├── validation.bats       # validate_number, validate_range, validate_yes
│   ├── instance.bats         # instance_gateway_port, instance_bridge_port, instance_name, instance_dir
│   ├── targets.bats          # expand_targets
│   └── safety.bats           # is_safe_token, safe_path_component
└── README.md
```

## Ejecutar

```bash
make test-unit
# o directamente:
./scripts/test-unit.sh
```

## Convenciones

- Cada `.bats` agrupa tests por módulo lógico.
- Los tests son **puros**: no requieren Docker, ni red, ni estado.
- Las funciones bajo prueba viven en `lib/cluster.sh`.
- Para añadir una nueva función testable:
  1. Agrégala a `lib/cluster.sh` (sin side effects).
  2. Crea/edita un `.bats` que la cubra.
  3. `make test-unit` debe pasar.

## Integración (futuro)

`tests/integration/` albergará pruebas con Docker real. No se ejecutan en CI por defecto (requieren trigger manual) para mantener el feedback rápido.
