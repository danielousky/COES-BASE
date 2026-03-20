
APLICACIÓN PARA EL CONTROL Y GESTIÓN DE ESTUDIANTES
CONTROL DE ESTUDIOS

DESARROLLADO POR DANIEL MOROS

Rails app generated with [lewagon/rails-templates](https://github.com/lewagon/rails-templates), created by the [Le Wagon coding bootcamp](https://www.lewagon.com) team.

## Delayed Job en producción (Dokku)

Para procesos pesados (como generación masiva de actas), usar **worker persistente** y no depender de `cron + jobs:workoff`.

### 1) Escalar proceso worker

```bash
dokku ps:scale coes-base web=1 worker=1
dokku ps:report coes-base
```

### 2) Verificar que el worker consuma la cola

```bash
dokku logs coes-base -p worker -t
```

### 3) Revisar jobs pendientes/fallidos

```bash
dokku run coes-base rails runner "puts \"pending=#{Delayed::Job.where(failed_at: nil).count} failed=#{Delayed::Job.where.not(failed_at: nil).count}\""
```

### 4) Cron (opcional solo para otras tareas)

Si se usa cron para otros scripts, no ejecutar `jobs:workoff` para la cola principal de Delayed Job.
En caso de contingencia, ejecutar manualmente:

```bash
dokku run coes-base rake jobs:workoff
```
