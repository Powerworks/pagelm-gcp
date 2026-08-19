import cors from 'cors';
import fs from 'fs'
import path from 'path'
import server from '../utils/server/server'
import { registerRoutes } from './router'
import { loggerMiddleware } from './middleware'

const envPath = path.resolve(process.cwd(), '.env')
if (fs.existsSync(envPath)) {
  process.loadEnvFile(envPath)
}

const app = server()

app.use(loggerMiddleware)


app.use(cors({
  origin: "*",
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
  credentials: true,
}));

const allowedOrigin = process.env.FRONTEND_URL || '*';

app.use(cors({
  origin: allowedOrigin === '*' ? '*' : [allowedOrigin, 'http://localhost:5173'],
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
  credentials: true,
}));
app.options('*', cors());

app.use(app.serverStatic("/storage", "./storage"))

registerRoutes(app)

app.listen(Number.parseInt(process.env.PORT || '5000'), () => {
  console.log(`[pagelm] running on ${process.env.VITE_BACKEND_URL}`)
})