// Yourider test entry: renders one shotcraft demo unchanged (proof the install renders).
import React from 'react';
import { Composition, registerRoot } from 'remotion';
import { DeckDealFlyin, DECK_DEAL_FLYIN_DURATION } from '../../../demos/ui-entrance/deck-deal-flyin/DeckDealFlyin';

const Root: React.FC = () => (
  <Composition id="DeckDealFlyin" component={DeckDealFlyin} durationInFrames={DECK_DEAL_FLYIN_DURATION} fps={30} width={1920} height={1080} />
);
registerRoot(Root);
