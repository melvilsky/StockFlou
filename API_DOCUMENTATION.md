# AI Stock Keywords API - Документация

## Обзор

AI Stock Keywords API позволяет генерировать AI-метаданные для загруженных изображений. API создает заголовки, описания и ключевые слова для стоковых фотографий с использованием искусственного интеллекта.

**Базовый URL:** `https://www.aistockkeywords.com/api/public/v1`

## Аутентификация

Для использования API требуется API ключ, который можно получить на странице аккаунта.

## Основные эндпоинты

### Генерация метаданных

**POST** `/generate-metadata`

Генерирует AI-метаданные для загруженного изображения.

#### Параметры запроса

| Параметр | Тип | Обязательный | Описание |
|----------|-----|--------------|----------|
| `apiKey` | string | ✅ | API ключ пользователя для аутентификации |
| `file` | File | ✅ | Изображение для обработки |
| `contextAndInstructions` | string | ❌ | Дополнительный контекст или инструкции для генерации метаданных |
| `numberOfKeywords` | number | ❌ | Количество генерируемых ключевых слов (по умолчанию: 49) |
| `shortTitle` | boolean | ❌ | Генерировать ли короткий заголовок |
| `englishLettersOnly` | boolean | ❌ | Ограничить ключевые слова только английскими буквами |
| `oneWordKeywordsOnly` | boolean | ❌ | Ограничить ключевые слова только одним словом |
| `keywordsPhrasesPreferred` | boolean | ❌ | Предпочитать фразы-ключевые слова вместо отдельных слов |

#### Формат запроса

```
Content-Type: multipart/form-data
```

#### Коды ответов

| Код | Описание |
|-----|----------|
| 200 | Успешная генерация метаданных |
| 400 | Отсутствуют или неверные параметры |
| 401 | Неверный API ключ |
| 403 | Недостаточно средств на балансе |
| 500 | Внутренняя ошибка сервера |

#### Пример запроса

```bash
curl -X POST \
  "https://www.aistockkeywords.com/api/public/v1/generate-metadata?apiKey=YOUR_API_KEY&numberOfKeywords=6&shortTitle=true" \
  -H "Content-Type: multipart/form-data" \
  -F "file=@/path/to/your/image.jpg"
```

#### Пример ответа

```json
{
  "title": "Sunset over the mountains",
  "description": "A beautiful sunset casting warm colors over a mountain landscape.",
  "keywords": [
    "sunset",
    "mountains", 
    "landscape",
    "nature",
    "sky",
    "scenery"
  ]
}
```

## Примеры использования

### Python

```python
import requests

def generate_metadata(api_key, image_path, **kwargs):
    """
    Генерирует метаданные для изображения
    
    Args:
        api_key (str): API ключ
        image_path (str): Путь к изображению
        **kwargs: Дополнительные параметры
    
    Returns:
        dict: Сгенерированные метаданные
    """
    url = "https://www.aistockkeywords.com/api/public/v1/generate-metadata"
    
    # Параметры запроса
    params = {
        'apiKey': api_key,
        **kwargs
    }
    
    # Файл изображения
    with open(image_path, 'rb') as f:
        files = {'file': f}
        
        response = requests.post(url, params=params, files=files)
        
        if response.status_code == 200:
            return response.json()
        else:
            raise Exception(f"Ошибка API: {response.status_code} - {response.text}")

# Пример использования
try:
    metadata = generate_metadata(
        api_key="YOUR_API_KEY",
        image_path="sunset.jpg",
        numberOfKeywords=10,
        shortTitle=True,
        englishLettersOnly=True
    )
    
    print(f"Заголовок: {metadata['title']}")
    print(f"Описание: {metadata['description']}")
    print(f"Ключевые слова: {', '.join(metadata['keywords'])}")
    
except Exception as e:
    print(f"Ошибка: {e}")
```

### JavaScript (Node.js)

```javascript
const FormData = require('form-data');
const fs = require('fs');
const axios = require('axios');

async function generateMetadata(apiKey, imagePath, options = {}) {
    const url = 'https://www.aistockkeywords.com/api/public/v1/generate-metadata';
    
    const form = new FormData();
    form.append('file', fs.createReadStream(imagePath));
    
    // Добавляем параметры в URL
    const params = new URLSearchParams({
        apiKey: apiKey,
        ...options
    });
    
    try {
        const response = await axios.post(`${url}?${params}`, form, {
            headers: {
                ...form.getHeaders()
            }
        });
        
        return response.data;
    } catch (error) {
        throw new Error(`Ошибка API: ${error.response?.status} - ${error.response?.data}`);
    }
}

// Пример использования
generateMetadata('YOUR_API_KEY', 'sunset.jpg', {
    numberOfKeywords: 8,
    shortTitle: true,
    englishLettersOnly: true
})
.then(metadata => {
    console.log('Заголовок:', metadata.title);
    console.log('Описание:', metadata.description);
    console.log('Ключевые слова:', metadata.keywords.join(', '));
})
.catch(error => {
    console.error('Ошибка:', error.message);
});
```

### PHP

```php
<?php

function generateMetadata($apiKey, $imagePath, $options = []) {
    $url = 'https://www.aistockkeywords.com/api/public/v1/generate-metadata';
    
    // Подготавливаем параметры
    $params = array_merge(['apiKey' => $apiKey], $options);
    $url .= '?' . http_build_query($params);
    
    // Подготавливаем файл
    $postData = [
        'file' => new CURLFile($imagePath)
    ];
    
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, $url);
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, $postData);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    
    $response = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    
    if ($httpCode === 200) {
        return json_decode($response, true);
    } else {
        throw new Exception("Ошибка API: $httpCode - $response");
    }
}

// Пример использования
try {
    $metadata = generateMetadata('YOUR_API_KEY', 'sunset.jpg', [
        'numberOfKeywords' => 6,
        'shortTitle' => true
    ]);
    
    echo "Заголовок: " . $metadata['title'] . "\n";
    echo "Описание: " . $metadata['description'] . "\n";
    echo "Ключевые слова: " . implode(', ', $metadata['keywords']) . "\n";
    
} catch (Exception $e) {
    echo "Ошибка: " . $e->getMessage() . "\n";
}

?>
```

## Лучшие практики

### 1. Обработка ошибок

Всегда обрабатывайте возможные ошибки API:

```python
try:
    metadata = generate_metadata(api_key, image_path)
except requests.exceptions.RequestException as e:
    print(f"Ошибка сети: {e}")
except Exception as e:
    print(f"Ошибка API: {e}")
```

### 2. Валидация параметров

Проверяйте параметры перед отправкой:

```python
def validate_params(numberOfKeywords, shortTitle, englishLettersOnly):
    if numberOfKeywords and (numberOfKeywords < 1 or numberOfKeywords > 100):
        raise ValueError("numberOfKeywords должен быть от 1 до 100")
    
    if shortTitle not in [True, False, None]:
        raise ValueError("shortTitle должен быть boolean")
```

### 3. Оптимизация запросов

- Используйте подходящее количество ключевых слов
- Предоставляйте контекст для лучших результатов
- Кэшируйте результаты для повторных запросов

### 4. Безопасность

- Никогда не передавайте API ключ в клиентском коде
- Используйте HTTPS для всех запросов
- Храните API ключи в переменных окружения

## Ограничения

- Максимальный размер файла: уточните в документации
- Поддерживаемые форматы: JPEG, PNG, GIF
- Лимиты запросов: уточните в документации
- Баланс аккаунта должен быть положительным

## Поддержка

Для получения поддержки обратитесь к официальной документации или в службу поддержки AI Stock Keywords.

---

*Документация основана на официальном API [AI Stock Keywords](https://www.aistockkeywords.com/api/public/v1/docs)*
