import React from 'react';
import { render } from 'ink';
import { App } from './ui/App.jsx';
import * as store from './io/store.js';

const root = process.argv[2] || store.defaultRoot();
render(<App root={root} />);
