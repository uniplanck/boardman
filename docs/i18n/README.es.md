# Board-Man

[English](../../README.md) / [ja](README.ja.md) / [zh-CN](README.zh-CN.md) / [es](README.es.md) / [pt-BR](README.pt-BR.md) / [ko](README.ko.md) / [de](README.de.md) / [fr](README.fr.md)

Board-Man es una app de productividad para el portapapeles de macOS derivada de Clipy.

Mantiene el historial del portapapeles disponible desde la barra de menús y añade visibilidad orientada al flujo de trabajo para quienes copian, pegan, editan y mueven con frecuencia texto, URL, comandos e imágenes entre apps.

> Estado: candidato público. Este repositorio es una edición de código abierto saneada a partir de una compilación privada en desarrollo activo.

## Captura de pantalla

![Board-Man main screenshot](../assets/board-man-main-screenshot.png)

## Qué puede hacer Board-Man

- Mantener el historial reciente del portapapeles disponible desde la barra de menús.
- Guardar y pegar snippets reutilizables.
- Mostrar insignias de recuento de pegados para los elementos usados con frecuencia.
- Gestionar entradas de imagen del portapapeles, incluido contenido solo de imagen similar a capturas de pantalla.
- Buscar en el historial del portapapeles.
- Navegar por el panel con el teclado.
- Fijar elementos importantes.
- Ajustar atajos, límites del historial, comportamiento del menú y opciones de tema visual.
- Ejecutarse localmente en macOS sin enviar el contenido del portapapeles a un servicio externo.

## Descarga

- [Descargar Board-Man v1.2.3](https://github.com/uniplanck/boardman/releases/tag/v1.2.3)
- Archivo de la app para macOS: `Board-Man-v1.2.3.zip`

## Instalación y primer inicio

1. Descarga `Board-Man-v1.2.3.zip` desde la página de la versión.
2. Descomprime el archivo.
3. Mueve `Board-Man.app` a `/Applications`.
4. Abre Board-Man.

Si macOS Gatekeeper bloquea el primer inicio, abre **System Settings > Privacy & Security** y permite Board-Man, o haz Control-click en la app y elige **Open**.

## Uso básico

1. Copia texto, una URL, un comando o una imagen como de costumbre.
2. Abre Board-Man desde la barra de menús.
3. Busca o desplázate por el historial del portapapeles.
4. Selecciona un elemento para pegarlo en la app activa.
5. Usa snippets para el texto que pegas repetidamente.

## Historial del portapapeles

Board-Man guarda los elementos recientes del portapapeles para que puedas volver a textos, URL, comandos y entradas de imagen sin copiarlos otra vez.

Úsalo cuando quieras:

- reutilizar algo copiado antes
- evitar cambiar entre documentos solo para copiar el mismo texto de nuevo
- tener a mano comandos o URL recientes
- revisar el flujo de trabajo con mucho copiar y pegar

## Snippets

Los snippets son entradas de texto reutilizables para frases, plantillas, URL, comandos y otros contenidos que pegas a menudo.

Usos habituales:

- respuestas repetidas
- plantillas de comandos
- bloques de texto para marketing o redes sociales
- mensajes de soporte
- URL y texto breve reutilizable

## Insignias de recuento de pegados

Las insignias de recuento de pegados muestran cuántas veces se ha pegado un elemento.

Esto ayuda a detectar:

- texto que reutilizas a menudo
- comandos que ejecutas repetidamente
- recursos o snippets centrales en tu flujo de trabajo
- patrones de copiar y pegar que quizá convenga convertir en snippets o automatización

## Soporte para imágenes del portapapeles

Board-Man admite entradas de imagen del portapapeles y puede mostrar contenido solo de imagen en la lista del historial.

Es útil al copiar:

- capturas de pantalla
- gráficos
- referencias de diseño
- contenido visual del portapapeles entre apps

Las entradas de imagen usan una identidad basada en marca de tiempo para que nombres genéricos como `TIFF image` o `PNG image` no colisionen en los recuentos de pegado.

## Búsqueda y navegación con teclado

Usa la búsqueda para filtrar el historial del portapapeles. El panel está diseñado para usarse con el teclado, de modo que puedas buscar, moverte por los resultados y pegar sin salir del flujo de trabajo actual.

## Ajustes y apariencia

Board-Man incluye ajustes para el comportamiento del menú, atajos, límites del historial y apariencia visual. Según la compilación actual, puedes usar opciones de tema y visualización más clara para que el panel sea más fácil de leer.

## Privacidad

Board-Man es una utilidad local para macOS. La app gestiona el contenido del portapapeles localmente. No guardes secretos, tokens, contraseñas ni datos privados de clientes en el historial del portapapeles a menos que entiendas el riesgo.

## Licencia y atribución

Board-Man es una obra derivada muy modificada basada en Clipy.

Este repositorio conserva la atribución y los avisos de licencia del proyecto original:

- `ATTRIBUTION.md`
- `LICENSE`
- `LICENSE_CLIPMENU`

Board-Man se distribuye bajo los términos de la licencia MIT heredados de Clipy. No está respaldado por los mantenedores originales de Clipy ni de ClipMenu.
