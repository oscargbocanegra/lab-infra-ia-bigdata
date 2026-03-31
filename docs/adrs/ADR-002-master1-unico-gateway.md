# ADR-002: master1 como único gateway LAN

**Fecha**: 2025-12  
**Estado**: Aceptado

---

## Contexto

Con 2 nodos necesitamos decidir dónde corre el reverse proxy (Traefik) que expone los servicios a la LAN. Opciones:

1. Traefik en master1 únicamente
2. Traefik en master2 únicamente
3. Traefik en ambos nodos (HA con keepalived/VIP)

---

## Decisión

**Traefik corre solo en master1** con `mode: host` en los puertos :80 y :443.

---

## Motivos

1. **Simplicidad de certificados**: Un solo punto de entrada → un solo par cert/key que gestionar. No hay que sincronizar certs entre nodos.

2. **master2 libre para workloads**: master2 tiene la GPU, el NVMe y la RAM comprometida con Jupyter + Ollama. Agregarle la carga de gateway quitaría recursos a los workloads reales.

3. **LAN-only no necesita HA**: No hay SLA de producción. Si master1 cae, el lab queda en mantenimiento. Aceptable para un entorno de lab.

4. **`mode: host` en master1**: Garantiza que :443 esté disponible directamente en la IP de master1 (`192.168.80.100`), sin el routing mesh de Swarm que puede interferir con certificados TLS.

5. **Un solo hostname para todo el /etc/hosts**: Todos los `*.sexydad` apuntan a `192.168.80.100`. Simple.

---

## Consecuencias

- ✅ Setup simple, un certificado, un punto de entrada
- ✅ master2 sin overhead de proxy
- ⚠️ Si master1 cae, todos los servicios son inaccesibles desde la LAN (aceptado para lab)
- ⚠️ Si en el futuro se necesita HA, agregar keepalived + VIP entre nodos
