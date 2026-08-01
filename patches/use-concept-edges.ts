import { computed, type ComputedRef } from 'vue';
import type { Router } from 'vue-router';
// glossarist-js's top-level d.ts is incomplete for v3 model fields.
// Import the MECE-augmented types from glossarist/models (extended by
// src/adapters/non-verbal/glossarist-augment.d.ts).
import type { Concept, RelatedConcept, ConceptRef } from 'glossarist';
import type {
  PartitiveRelation as GlsPartitiveRelation,
  PartitiveMember as GlsPartitiveMember,
} from 'glossarist/models';
import type {
  Manifest,
  GraphEdge,
  PartitiveRelationWire,
  PartitiveMemberWire,
} from '../adapters/types';
import { getFactory } from '../adapters/factory';
import { conceptUri } from '../adapters/model-bridge';
import { UriRouter } from '../adapters/UriRouter';
import { useVocabularyStore } from '../stores/vocabulary';
import { useDsStyle } from '../utils/dataset-style';
import { categorizeRelationship, relationshipLabel, INVERSE_RELATIONSHIPS } from '../utils/relationship-categories';
import { langLabel } from '../utils/lang';
import { escapeAttr } from '../utils/escape';
import { useI18n } from '../i18n';
import { type PartitivePresence, type PartitiveCount } from '../utils/partitive-multiplicity';

export interface EdgeDisplay {
  uri: string;
  conceptId: string;
  designation: string;
  tooltip: string;
  isLocal: boolean;
  badge: { id: string; title: string } | null;
}

export function useConceptEdges(
  concept: ComputedRef<Concept>,
  registerId: ComputedRef<string>,
  manifest: ComputedRef<Manifest>,
  edges: ComputedRef<GraphEdge[]>,
  router: Router,
) {
  const factory = getFactory();
  const store = useVocabularyStore();
  const { getColor } = useDsStyle();
  const { locale } = useI18n();

  const conceptUriValue = computed(() =>
    conceptUri(concept.value, registerId.value, manifest.value.uriBase)
  );

  const outgoingEdges = computed(() =>
    store.graph.getUniqueEdges(conceptUriValue.value, 'outgoing', 'target')
      .filter(e => e.type !== 'domain' && e.type !== 'section')
  );

  const incomingEdges = computed(() =>
    store.graph.getUniqueEdges(conceptUriValue.value, 'incoming', 'source')
      .filter(e => e.type !== 'domain' && e.type !== 'section')
  );

  const edgeDisplayCache = computed(() => {
    const cache = new Map<string, EdgeDisplay>();
    for (const e of edges.value) {
      const uri = e.source === conceptUriValue.value ? e.target : e.source;
      if (cache.has(uri)) continue;
      const resolution = factory.resolve(uri, registerId.value);
      const isLocal = resolution.type === 'internal' && resolution.registerId === registerId.value;
      const conceptId = uri.match(/\/concept\/([^/]+)$/)?.[1] ?? uri.split('/').pop() ?? uri;
      const node = store.graph.getNode(uri);
      const designation = node
        ? (node.designations[locale.value] || node.designations.eng || Object.values(node.designations)[0] || '')
        : '';
      const tooltipLines: string[] = [conceptId];
      if (node) {
        for (const [lang, des] of Object.entries(node.designations)) {
          tooltipLines.push(`${langLabel(lang)}: ${des}`);
        }
      }
      tooltipLines.push(uri);
      let badge: { id: string; title: string } | null = null;
      if (resolution.type === 'internal' && resolution.registerId !== registerId.value) {
        const m = store.manifests.get(resolution.registerId);
        badge = { id: resolution.registerId, title: m?.shortname || m?.title || resolution.registerId };
      } else if (resolution.type === 'site') {
        badge = { id: '', title: resolution.label };
      } else if (resolution.type === 'url') {
        badge = { id: '', title: resolution.label };
      }
      cache.set(uri, { uri, conceptId, designation, tooltip: tooltipLines.join('\n'), isLocal, badge });
    }
    return cache;
  });

  function getEdgeDisplay(uri: string): EdgeDisplay {
    return edgeDisplayCache.value.get(uri) ?? { uri, conceptId: uri, designation: '', tooltip: uri, isLocal: false, badge: null };
  }

  /**
   * Resolve a concept's designation in the current UI locale.
   * Fallback chain: locale → eng → any available.
   *
   * Sources tried in order:
   *   1. BFS graph node (already loaded as a neighbor)
   *   2. Dataset adapter index entry (every concept in the dataset)
   *   3. conceptId as last-resort fallback
   *
   * Used by PartitiveRelationList (sidebar rake diagram) so the rake
   * shows designations like 'system of quantities' instead of bare
   * IDs like '1.3'.
   */
  function designationFor(uri: string): string {
    const node = store.graph.getNode(uri);
    if (node) {
      const des = node.designations[locale.value]
        || node.designations.eng
        || Object.values(node.designations)[0];
      if (des) return des;
    }
    const resolution = factory.resolve(uri);
    if (resolution.type === 'internal') {
      const adapter = store.datasets.get(resolution.registerId);
      const entry = adapter?.getIndexEntry(resolution.conceptId);
      if (entry) {
        const des = entry.designations[locale.value]
          || entry.designations.eng
          || Object.values(entry.designations)[0];
        if (des) return des;
      }
    }
    return resolution.type === 'internal' ? resolution.conceptId : uri;
  }

  function edgeBadgeColor(type: string, direction: 'out' | 'in'): string {
    if (type === 'supersedes' || type === 'superseded_by') {
      return direction === 'out' ? 'text-orange-700 bg-orange-50' : 'text-red-700 bg-red-50';
    }
    return categorizeRelationship(type).color;
  }

  function inverseEdgeType(type: string): string {
    return INVERSE_RELATIONSHIPS[type] || type;
  }

  // Concept-level related concepts (managed concept cross-references)
  const conceptRelated = computed(() => {
    const direct = concept.value.relatedConcepts?.filter(rc => !INVERSE_RELATIONSHIPS[rc.type]) ?? [];
    const derived = incomingEdges.value
      .filter(e => INVERSE_RELATIONSHIPS[e.type])
      .map(e => {
        const parsed = factory.resolve(e.source, registerId.value);
        const sourceUrn = parsed.type === 'internal'
          ? store.manifests.get(parsed.registerId)?.datasetUri
          : null;
        const conceptId = e.source.match(/\/concept\/([^/]+)$/)?.[1];
        return {
          type: INVERSE_RELATIONSHIPS[e.type],
          ref: sourceUrn && conceptId ? { source: sourceUrn, id: conceptId } : null,
          content: '',
        };
      });
    return [...direct, ...derived].filter(edge => {
      if (edge.type === 'broader_partitive' || edge.type === 'narrower_partitive') {
        const refUri = resolveRefUri(edge.ref as { source: string | null; id: string | null } | null);
        if (!refUri) return true;
        const rels = conceptPartitiveRelations.value;
        return !rels.some(rel =>
          rel.comprehensive === refUri
          || rel.partitives.some(m => m.uri === refUri),
        );
      }
      return true;
    });
  });

  // Concept-level partitive relations (ISO 704 one-to-many decompositions).
  // Reads the glossarist-js native model (`concept.partitiveRelations`)
  // and projects each relation into a URI-resolved wire shape for display.
  // Independent of binary `conceptRelated`.
  // v2 shape per concept-model/TODO.partitive-relation-v2.
  const conceptPartitiveRelations = computed<PartitiveRelationWire[]>(() => {
    const source = conceptUriValue.value;
    const relations: readonly GlsPartitiveRelation[] = concept.value.partitiveRelations;
    return relations
      .map((rel): PartitiveRelationWire | null => {
        const comprehensive = resolveConceptRefUri(rel.comprehensive);
        if (!comprehensive) return null;
        const partitives: PartitiveMemberWire[] = rel.partitives
          .map((m: GlsPartitiveMember): PartitiveMemberWire | null => {
            const uri = resolveConceptRefUri(m.ref);
            if (!uri || uri === source) return null;
            return {
              uri,
              presence: readPresence(m),
              count: readCount(m),
              isDelimiting: readIsDelimiting(m),
            };
          })
          .filter((m: PartitiveMemberWire | null): m is PartitiveMemberWire => m !== null);
        if (partitives.length === 0) return null;

        return {
          source,
          comprehensive,
          partitives,
          completeness: rel.completeness,
          criterion: rel.criterion ?? undefined,
          register: registerId.value,
        };
      })
      .filter((r: PartitiveRelationWire | null): r is PartitiveRelationWire => r !== null);
  });

  function resolveConceptRefUri(ref: ConceptRef | null): string | null {
    if (!ref) return null;
    return resolveRefUri({ source: ref.source ?? null, id: ref.id ?? null });
  }

  // Read presence + count directly from the glossarist-js model
  // (MECE native, since glossarist 0.4.26).
  function readPresence(m: GlsPartitiveMember): PartitivePresence {
    return m.presence;
  }

  function readCount(m: GlsPartitiveMember): PartitiveCount {
    return m.count;
  }

  function readIsDelimiting(m: GlsPartitiveMember): boolean {
    return m.is_delimiting === true;
  }

  function resolveRefUri(ref: { source: string | null; id: string | null } | null): string | null {
    const target = resolveRelatedRef(ref);
    if (!target) return null;
    const m = store.manifests.get(target.registerId);
    if (!m) return null;
    return UriRouter.buildConceptUri(m.uriBase, target.registerId, target.conceptId);
  }

  function resolveRelatedRef(ref: { source: string | null; id: string | null } | null) {
    return factory.resolveRelatedRef(ref, registerId.value);
  }

  const resolvedRefs = computed(() => {
    const map = new Map<string, { target: { registerId: string; conceptId: string } | null }>();
    for (const cr of conceptRelated.value) {
      const key = `${cr.ref?.source ?? ''}:${cr.ref?.id ?? ''}`;
      if (map.has(key)) continue;
      map.set(key, { target: resolveRelatedRef(cr.ref) });
    }
    return map;
  });

  function getResolvedRef(ref: { source: string | null; id: string | null } | null) {
    if (!ref) return { target: null };
    const key = `${ref.source ?? ''}:${ref.id ?? ''}`;
    return resolvedRefs.value.get(key) ?? { target: resolveRelatedRef(ref) };
  }

  function relatedLabel(dr: { content?: Record<string, string> | string | null; ref?: { source: string | null; id: string | null } | null }): string {
    if (dr.content) {
      // Content is a localized hash { eng: "...", fra: "..." }.
      // Legacy data may still carry a plain string; tolerate both.
      const c = dr.content as Record<string, string> | string;
      if (typeof c === 'string') return c;
      const values = Object.values(c);
      if (values.length > 0) return values[0];
    }
    const resolved = dr.ref ? getResolvedRef(dr.ref).target : null;
    if (resolved) {
      const m = store.manifests.get(resolved.registerId);
      const dsLabel = m?.shortname || m?.title || resolved.registerId;
      return `${resolved.conceptId} (${dsLabel})`;
    }
    return dr.ref ? `${dr.ref.id || ''} (${dr.ref.source || ''})`.trim() : '';
  }

  async function navigateEdge(edge: GraphEdge) {
    const uri = edge.source === conceptUriValue.value ? edge.target : edge.source;
    const resolution = factory.resolve(uri);

    if (resolution.type === 'internal') {
      router.push({ name: 'concept', params: { registerId: resolution.registerId, conceptId: resolution.conceptId } });
    } else if (resolution.type === 'site') {
      window.open(`${resolution.baseUrl}/resolve/${encodeURIComponent(uri)}`, '_blank', 'noopener');
    } else if (resolution.type === 'url') {
      window.open(resolution.url, '_blank', 'noopener');
    }
  }

  async function navigateRelated(ref: { source: string | null; id: string | null }) {
    const target = resolveRelatedRef(ref);
    if (!target) return;
    router.push({ name: 'concept', params: { registerId: target.registerId, conceptId: target.conceptId } });
  }

  return {
    conceptUriValue,
    outgoingEdges,
    incomingEdges,
    edgeDisplayCache,
    getEdgeDisplay,
    designationFor,
    edgeBadgeColor,
    inverseEdgeType,
    conceptRelated,
    conceptPartitiveRelations,
    resolveRelatedRef,
    getResolvedRef,
    relatedLabel,
    navigateEdge,
    navigateRelated,
  };
}
