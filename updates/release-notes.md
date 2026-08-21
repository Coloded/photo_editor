# Photo_Editor 1.5

## English

- Reworked the blur brush for large, high-resolution photographs.
- Interactive brush rendering now uses a Metal preview capped at 2048 pixels.
- The full-resolution original is preserved and used when exporting the final file.
- Blur intensity now scales with image resolution, keeping preview and export visually consistent.
- Reduced UI stalls, memory pressure, and growth of the Core Image filter graph while painting.

## Русский

- Переработана кисть размытия для больших фотографий с высоким разрешением.
- Во время работы кисти используется Metal-предпросмотр размером не более 2048 пикселей.
- Полноразмерный оригинал сохраняется и применяется при экспорте итогового файла.
- Интенсивность размытия масштабируется вместе с изображением, поэтому предпросмотр соответствует экспорту.
- Уменьшены задержки интерфейса, расход памяти и рост цепочки фильтров Core Image.
