const http = require('http');

http.get('http://localhost:5000/api/sessions?status=history', (res) => {
  let data = '';
  res.on('data', chunk => data += chunk);
  res.on('end', () => {
    try {
      const parsed = JSON.parse(data);
      console.log('Total sessions returned:', parsed.length);
      console.log(parsed.slice(0, 3));
    } catch(e) {
      console.error(e.message, data);
    }
  });
}).on('error', console.error);
