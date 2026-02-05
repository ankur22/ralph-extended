import { useCallback, useState, useRef } from 'react';
import type { Node, Edge, NodeChange, EdgeChange, Connection } from '@xyflow/react';
import {
  ReactFlow,
  useNodesState,
  useEdgesState,
  Controls,
  Background,
  BackgroundVariant,
  MarkerType,
  applyNodeChanges,
  applyEdgeChanges,
  addEdge,
  Handle,
  Position,
  reconnectEdge,
} from '@xyflow/react';
import '@xyflow/react/dist/style.css';
import './App.css';

const nodeWidth = 240;
const nodeHeight = 70;

// Phases for Ralph Extended multi-agent workflow
type Phase = 'setup' | 'research' | 'backend' | 'frontend' | 'qa' | 'decision' | 'done';

const phaseColors: Record<Phase, { bg: string; border: string }> = {
  setup: { bg: '#f0f7ff', border: '#4a90d9' },
  research: { bg: '#f5f0ff', border: '#8b5cf6' },
  backend: { bg: '#fff0f0', border: '#e53e3e' },
  frontend: { bg: '#f0fff4', border: '#38a169' },
  qa: { bg: '#fff8e6', border: '#c9a227' },
  decision: { bg: '#f5f5f5', border: '#666666' },
  done: { bg: '#e6fffa', border: '#319795' },
};

const allSteps: { id: string; label: string; description: string; phase: Phase }[] = [
  // Setup phase
  { id: '1', label: 'Write PRD', description: 'Use /prd skill to define feature', phase: 'setup' },
  { id: '2', label: 'Research (optional)', description: 'Explore codebase & external docs', phase: 'research' },
  { id: '3', label: 'Convert to prd.json', description: 'Set layers per story', phase: 'setup' },
  { id: '4', label: 'Run ralph-extended.sh', description: '--tool claude|codex|amp', phase: 'setup' },
  // Orchestrator picks story
  { id: '5', label: 'Pick next story', description: 'Orchestrator finds passes: false', phase: 'decision' },
  // Backend phase
  { id: '6', label: 'Backend Dev', description: 'Implements API/DB changes', phase: 'backend' },
  { id: '7', label: 'Backend Review', description: 'Code review & security check', phase: 'backend' },
  // Frontend phase
  { id: '8', label: 'Frontend Dev', description: 'Implements UI components', phase: 'frontend' },
  { id: '9', label: 'Frontend Review', description: 'A11y, UX & code review', phase: 'frontend' },
  // QA phase
  { id: '10', label: 'QA Testing', description: 'k6 functional + e2e tests', phase: 'qa' },
  // Decision
  { id: '11', label: 'Tests pass?', description: '', phase: 'decision' },
  // Issue routing
  { id: '12', label: 'Route by layer', description: 'Backend or Frontend issues?', phase: 'decision' },
  // More stories decision
  { id: '13', label: 'More stories?', description: '', phase: 'decision' },
  // Done
  { id: '14', label: 'Done!', description: 'All stories complete', phase: 'done' },
];

const notes = [
  {
    id: 'note-1',
    appearsWithStep: 2,
    position: { x: 480, y: 40 },
    color: { bg: '#f5f0ff', border: '#8b5cf6' },
    content: `Research Phase:
• Codebase exploration
• Official docs & GitHub issues
• Saves to tasks/research-*.md`,
  },
  {
    id: 'note-2',
    appearsWithStep: 3,
    position: { x: 480, y: 180 },
    color: { bg: '#f0f7ff', border: '#4a90d9' },
    content: `Per-Story Layers:
• Backend only: API, DB, logic
• Frontend only: UI changes
• Both: Full pipeline`,
  },
  {
    id: 'note-3',
    appearsWithStep: 4,
    position: { x: 480, y: 320 },
    color: { bg: '#e6fffa', border: '#319795' },
    content: `Tool Options:
• claude (default)
• codex (OpenAI)
• amp

Docker sandbox per feature`,
  },
  {
    id: 'note-4',
    appearsWithStep: 12,
    position: { x: 700, y: 780 },
    color: { bg: '#fff0f0', border: '#e53e3e' },
    content: `Issue Routing:
• API errors → Backend Dev
• UI errors → Frontend Dev
• Both → Backend first`,
  },
];

function CustomNode({ data }: { data: { title: string; description: string; phase: Phase } }) {
  const colors = phaseColors[data.phase];
  return (
    <div
      className="custom-node"
      style={{
        backgroundColor: colors.bg,
        borderColor: colors.border
      }}
    >
      <Handle type="target" position={Position.Top} id="top" />
      <Handle type="target" position={Position.Left} id="left" />
      <Handle type="source" position={Position.Right} id="right" />
      <Handle type="source" position={Position.Bottom} id="bottom" />
      <Handle type="target" position={Position.Right} id="right-target" style={{ right: 0 }} />
      <Handle type="target" position={Position.Bottom} id="bottom-target" style={{ bottom: 0 }} />
      <Handle type="source" position={Position.Top} id="top-source" />
      <Handle type="source" position={Position.Left} id="left-source" />
      <div className="node-content">
        <div className="node-title">{data.title}</div>
        {data.description && <div className="node-description">{data.description}</div>}
      </div>
    </div>
  );
}

function NoteNode({ data }: { data: { content: string; color: { bg: string; border: string } } }) {
  return (
    <div
      className="note-node"
      style={{
        backgroundColor: data.color.bg,
        borderColor: data.color.border,
      }}
    >
      <pre>{data.content}</pre>
    </div>
  );
}

const nodeTypes = { custom: CustomNode, note: NoteNode };

const positions: { [key: string]: { x: number; y: number } } = {
  // Setup phase (vertical on left)
  '1': { x: 20, y: 20 },
  '2': { x: 220, y: 20 },
  '3': { x: 20, y: 160 },
  '4': { x: 20, y: 300 },
  // Pick story
  '5': { x: 20, y: 440 },
  // Backend phase (right side, upper)
  '6': { x: 320, y: 440 },
  '7': { x: 320, y: 540 },
  // Frontend phase (right side, lower)
  '8': { x: 320, y: 640 },
  '9': { x: 320, y: 740 },
  // QA
  '10': { x: 20, y: 640 },
  // Decision: tests pass?
  '11': { x: 20, y: 780 },
  // Route by layer
  '12': { x: 320, y: 880 },
  // More stories?
  '13': { x: 20, y: 920 },
  // Done
  '14': { x: 20, y: 1060 },
  // Notes
  ...Object.fromEntries(notes.map(n => [n.id, n.position])),
};

const edgeConnections: { source: string; target: string; sourceHandle?: string; targetHandle?: string; label?: string }[] = [
  // Setup phase - Write PRD can go to research or directly to convert
  { source: '1', target: '2', sourceHandle: 'right', targetHandle: 'left', label: 'Research?' },
  { source: '2', target: '3', sourceHandle: 'bottom', targetHandle: 'right-target' },
  { source: '1', target: '3', sourceHandle: 'bottom', targetHandle: 'top', label: 'Skip' },
  { source: '3', target: '4', sourceHandle: 'bottom', targetHandle: 'top' },
  { source: '4', target: '5', sourceHandle: 'bottom', targetHandle: 'top' },

  // Pick story to agents (based on layer config)
  { source: '5', target: '6', sourceHandle: 'right', targetHandle: 'left', label: 'Backend' },
  { source: '5', target: '10', sourceHandle: 'bottom', targetHandle: 'top', label: 'Frontend only' },

  // Backend pipeline
  { source: '6', target: '7', sourceHandle: 'bottom', targetHandle: 'top' },
  { source: '7', target: '8', sourceHandle: 'bottom', targetHandle: 'top', label: 'Has Frontend' },
  { source: '7', target: '10', sourceHandle: 'left-source', targetHandle: 'right-target', label: 'Backend only' },

  // Frontend pipeline
  { source: '8', target: '9', sourceHandle: 'bottom', targetHandle: 'top' },
  { source: '9', target: '10', sourceHandle: 'left-source', targetHandle: 'right-target' },

  // QA to decision
  { source: '10', target: '11', sourceHandle: 'bottom', targetHandle: 'top' },

  // Tests pass decision
  { source: '11', target: '13', sourceHandle: 'bottom', targetHandle: 'top', label: 'Yes' },
  { source: '11', target: '12', sourceHandle: 'right', targetHandle: 'left', label: 'No' },

  // Issue routing back to devs
  { source: '12', target: '6', sourceHandle: 'top-source', targetHandle: 'bottom-target', label: 'Backend' },
  { source: '12', target: '8', sourceHandle: 'top-source', targetHandle: 'bottom-target', label: 'Frontend' },

  // More stories loop
  { source: '13', target: '5', sourceHandle: 'left-source', targetHandle: 'left', label: 'Yes' },
  { source: '13', target: '14', sourceHandle: 'bottom', targetHandle: 'top', label: 'No' },
];

function createNode(step: typeof allSteps[0], visible: boolean, position?: { x: number; y: number }): Node {
  return {
    id: step.id,
    type: 'custom',
    position: position || positions[step.id],
    data: {
      title: step.label,
      description: step.description,
      phase: step.phase,
    },
    style: {
      width: nodeWidth,
      height: nodeHeight,
      opacity: visible ? 1 : 0,
      transition: 'opacity 0.5s ease-in-out',
      pointerEvents: visible ? 'auto' : 'none',
    },
  };
}

function createEdge(conn: typeof edgeConnections[0], visible: boolean): Edge {
  return {
    id: `e${conn.source}-${conn.target}`,
    source: conn.source,
    target: conn.target,
    sourceHandle: conn.sourceHandle,
    targetHandle: conn.targetHandle,
    label: visible ? conn.label : undefined,
    animated: visible,
    style: {
      stroke: '#222',
      strokeWidth: 2,
      opacity: visible ? 1 : 0,
      transition: 'opacity 0.5s ease-in-out',
    },
    labelStyle: {
      fill: '#222',
      fontWeight: 600,
      fontSize: 12,
    },
    labelShowBg: true,
    labelBgPadding: [6, 3] as [number, number],
    labelBgStyle: {
      fill: '#fff',
      stroke: '#222',
      strokeWidth: 1,
    },
    markerEnd: {
      type: MarkerType.ArrowClosed,
      color: '#222',
    },
  };
}

function createNoteNode(note: typeof notes[0], visible: boolean, position?: { x: number; y: number }): Node {
  return {
    id: note.id,
    type: 'note',
    position: position || positions[note.id],
    data: { content: note.content, color: note.color },
    style: {
      opacity: visible ? 1 : 0,
      transition: 'opacity 0.5s ease-in-out',
      pointerEvents: visible ? 'auto' : 'none',
    },
    draggable: true,
    selectable: false,
    connectable: false,
  };
}

function App() {
  const [visibleCount, setVisibleCount] = useState(1);
  const nodePositions = useRef<{ [key: string]: { x: number; y: number } }>({ ...positions });

  const getNodes = (count: number) => {
    const stepNodes = allSteps.map((step, index) =>
      createNode(step, index < count, nodePositions.current[step.id])
    );
    const noteNodes = notes.map(note => {
      const noteVisible = count >= note.appearsWithStep;
      return createNoteNode(note, noteVisible, nodePositions.current[note.id]);
    });
    return [...stepNodes, ...noteNodes];
  };

  const initialNodes = getNodes(1);
  const initialEdges = edgeConnections.map((conn, index) =>
    createEdge(conn, index < 0)
  );

  const [nodes, setNodes] = useNodesState(initialNodes);
  const [edges, setEdges] = useEdgesState(initialEdges);

  const onNodesChange = useCallback(
    (changes: NodeChange[]) => {
      changes.forEach((change) => {
        if (change.type === 'position' && change.position) {
          nodePositions.current[change.id] = change.position;
        }
      });
      setNodes((nds) => applyNodeChanges(changes, nds));
    },
    [setNodes]
  );

  const onEdgesChange = useCallback(
    (changes: EdgeChange[]) => {
      setEdges((eds) => applyEdgeChanges(changes, eds));
    },
    [setEdges]
  );

  const onConnect = useCallback(
    (connection: Connection) => {
      setEdges((eds) => addEdge({ ...connection, animated: true, style: { stroke: '#222', strokeWidth: 2 }, markerEnd: { type: MarkerType.ArrowClosed, color: '#222' } }, eds));
    },
    [setEdges]
  );

  const onReconnect = useCallback(
    (oldEdge: Edge, newConnection: Connection) => {
      setEdges((eds) => reconnectEdge(oldEdge, newConnection, eds));
    },
    [setEdges]
  );

  const getEdgeVisibility = (conn: typeof edgeConnections[0], visibleStepCount: number) => {
    const sourceIndex = allSteps.findIndex(s => s.id === conn.source);
    const targetIndex = allSteps.findIndex(s => s.id === conn.target);
    return sourceIndex < visibleStepCount && targetIndex < visibleStepCount;
  };

  const handleNext = useCallback(() => {
    if (visibleCount < allSteps.length) {
      const newCount = visibleCount + 1;
      setVisibleCount(newCount);

      setNodes(getNodes(newCount));
      setEdges(
        edgeConnections.map((conn) =>
          createEdge(conn, getEdgeVisibility(conn, newCount))
        )
      );
    }
  }, [visibleCount, setNodes, setEdges]);

  const handlePrev = useCallback(() => {
    if (visibleCount > 1) {
      const newCount = visibleCount - 1;
      setVisibleCount(newCount);

      setNodes(getNodes(newCount));
      setEdges(
        edgeConnections.map((conn) =>
          createEdge(conn, getEdgeVisibility(conn, newCount))
        )
      );
    }
  }, [visibleCount, setNodes, setEdges]);

  const handleReset = useCallback(() => {
    setVisibleCount(1);
    nodePositions.current = { ...positions };
    setNodes(getNodes(1));
    setEdges(edgeConnections.map((conn, index) => createEdge(conn, index < 0)));
  }, [setNodes, setEdges]);

  return (
    <div className="app-container">
      <div className="header">
        <h1>How Ralph Extended Works</h1>
        <p>Multi-agent autonomous coding system with specialized agents</p>
      </div>
      <div className="flow-container">
        <ReactFlow
          nodes={nodes}
          edges={edges}
          nodeTypes={nodeTypes}
          onNodesChange={onNodesChange}
          onEdgesChange={onEdgesChange}
          onConnect={onConnect}
          onReconnect={onReconnect}
          fitView
          fitViewOptions={{ padding: 0.2 }}
          nodesDraggable={true}
          nodesConnectable={true}
          edgesReconnectable={true}
          elementsSelectable={true}
          deleteKeyCode={['Backspace', 'Delete']}
          panOnDrag={true}
          panOnScroll={true}
          zoomOnScroll={true}
          zoomOnPinch={true}
          zoomOnDoubleClick={true}
          selectNodesOnDrag={false}
        >
          <Background variant={BackgroundVariant.Dots} gap={20} size={1} color="#ddd" />
          <Controls showInteractive={false} />
        </ReactFlow>
      </div>
      <div className="controls">
        <button onClick={handlePrev} disabled={visibleCount <= 1}>
          Previous
        </button>
        <span className="step-counter">
          Step {visibleCount} of {allSteps.length}
        </span>
        <button onClick={handleNext} disabled={visibleCount >= allSteps.length}>
          Next
        </button>
        <button onClick={handleReset} className="reset-btn">
          Reset
        </button>
      </div>
      <div className="instructions">
        Click Next to reveal each step • Drag nodes to reposition
      </div>
      <div className="legend">
        <span style={{ backgroundColor: phaseColors.setup.bg, borderColor: phaseColors.setup.border }}>Setup</span>
        <span style={{ backgroundColor: phaseColors.research.bg, borderColor: phaseColors.research.border }}>Research</span>
        <span style={{ backgroundColor: phaseColors.backend.bg, borderColor: phaseColors.backend.border }}>Backend</span>
        <span style={{ backgroundColor: phaseColors.frontend.bg, borderColor: phaseColors.frontend.border }}>Frontend</span>
        <span style={{ backgroundColor: phaseColors.qa.bg, borderColor: phaseColors.qa.border }}>QA</span>
        <span style={{ backgroundColor: phaseColors.decision.bg, borderColor: phaseColors.decision.border }}>Decision</span>
        <span style={{ backgroundColor: phaseColors.done.bg, borderColor: phaseColors.done.border }}>Done</span>
      </div>
    </div>
  );
}

export default App;
