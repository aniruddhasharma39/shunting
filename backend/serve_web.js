const express = require('express');
const path = require('path');

const app = express();
const webDir = path.join(__dirname, '../frontend/build/web');

app.use(express.static(webDir));

app.use((req, res) => {
  res.sendFile(path.join(webDir, 'index.html'));
});

const PORT = 8080;
app.listen(PORT, () => {
  console.log(`Flutter Web App is serving at http://localhost:${PORT}`);
});
