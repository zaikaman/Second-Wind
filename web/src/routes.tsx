import { createBrowserRouter } from 'react-router-dom';
import { Layout } from './components/Layout';
import Dashboard from './pages/Dashboard';
import NewCover from './pages/NewCover';
import NotFound from './pages/NotFound';
import Policy from './pages/Policy';
import Proof from './pages/Proof';
import Receipt from './pages/Receipt';
import Receipts from './pages/Receipts';

export const router = createBrowserRouter([
  {
    path: '/',
    element: <Layout />,
    children: [
      { index: true, element: <Dashboard /> },
      { path: 'cover/new', element: <NewCover /> },
      { path: 'policies/:id', element: <Policy /> },
      { path: 'receipts', element: <Receipts /> },
      { path: 'receipts/:runId', element: <Receipt /> },
      { path: 'proof', element: <Proof /> },
      { path: '*', element: <NotFound /> },
    ],
  },
]);
