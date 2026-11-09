import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'models.dart';

class VerbaleBlock {
  const VerbaleBlock(this.kind, this.text);
  final String kind; // title, subtitle, heading, body, signature
  final String text;
}

String _or(String value, String placeholder) =>
    value.trim().isEmpty ? placeholder : value.trim();

/// Costruisce la struttura del documento, uguale per testo e Word.
List<VerbaleBlock> buildVerbaleBlocks(Verbale v) {
  final blocks = <VerbaleBlock>[];
  final type = v.tipoRiunione.trim();
  blocks.add(VerbaleBlock(
    'title',
    type.isEmpty ? 'VERBALE DI RIUNIONE' : 'VERBALE DI ${type.toUpperCase()}',
  ));
  if (v.ente.trim().isNotEmpty) blocks.add(VerbaleBlock('subtitle', v.ente.trim()));

  final opening = StringBuffer('Il giorno ${_or(v.data, '__________')}');
  opening.write(', alle ore ${_or(v.oraInizio, '_____')}');
  opening.write(', presso ${_or(v.luogo, '__________')}, si è riunito ');
  opening.write(type.isEmpty ? 'l\'organo in epigrafe' : 'il/la $type');
  opening.write('.');
  blocks.add(VerbaleBlock('body', opening.toString()));
  blocks.add(VerbaleBlock(
    'body',
    'Assume la presidenza ${_or(v.presidente, '__________')}; '
        'funge da segretario ${_or(v.segretario, '__________')}.',
  ));

  void section(String heading, String text) {
    if (text.trim().isEmpty) return;
    blocks.add(VerbaleBlock('heading', heading));
    for (final para in text.split(RegExp(r'\n+'))) {
      if (para.trim().isNotEmpty) blocks.add(VerbaleBlock('body', para.trim()));
    }
  }

  section('Presenti', v.presenti);
  section('Assenti', v.assenti);
  section('Ordine del giorno', v.ordineDelGiorno);
  section('Discussione', v.discussione);
  section('Delibere', v.delibere);
  section('Varie ed eventuali', v.varie);

  blocks.add(VerbaleBlock(
    'body',
    'Non essendovi altro da deliberare, la seduta è tolta alle ore '
        '${_or(v.oraFine, '_____')}.',
  ));
  blocks.add(const VerbaleBlock('heading', 'Letto, approvato e sottoscritto'));
  blocks.add(VerbaleBlock(
    'signature',
    'Il Presidente: ${_or(v.presidente, '')} ____________________',
  ));
  blocks.add(VerbaleBlock(
    'signature',
    'Il Segretario: ${_or(v.segretario, '')} ____________________',
  ));
  return blocks;
}

String verbaleToText(Verbale v) {
  final b = StringBuffer();
  for (final block in buildVerbaleBlocks(v)) {
    switch (block.kind) {
      case 'title':
        b.write('${block.text}\n');
      case 'subtitle':
        b.write('${block.text}\n\n');
      case 'heading':
        b.write('\n${block.text.toUpperCase()}\n');
      case 'signature':
        b.write('\n${block.text}\n');
      default:
        b.write('${block.text}\n');
    }
  }
  return b.toString();
}

String _xml(String s) => s
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

String _paragraph(VerbaleBlock block) {
  final style = switch (block.kind) {
    'title' => 'Titolo',
    'subtitle' => 'Sottotitolo',
    'heading' => 'Sezione',
    'signature' => 'Firma',
    _ => 'Corpo',
  };
  return '<w:p><w:pPr><w:pStyle w:val="$style"/></w:pPr>'
      '<w:r><w:t xml:space="preserve">${_xml(block.text)}</w:t></w:r></w:p>';
}

const _contentTypes = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
    '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
    '</Types>';

const _rels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
    '</Relationships>';

const _docRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
    '</Relationships>';

String _style(String id, String name, String pPr, String rPr) =>
    '<w:style w:type="paragraph" w:styleId="$id"><w:name w:val="$name"/>'
    '<w:pPr>$pPr</w:pPr><w:rPr>$rPr</w:rPr></w:style>';

final _styles = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
    '<w:docDefaults><w:rPrDefault><w:rPr>'
    '<w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:cs="Times New Roman"/>'
    '<w:sz w:val="24"/><w:lang w:val="it-IT"/></w:rPr></w:rPrDefault></w:docDefaults>'
    '${_style('Titolo', 'Titolo verbale', '<w:spacing w:after="120"/><w:jc w:val="center"/>', '<w:b/><w:sz w:val="30"/>')}'
    '${_style('Sottotitolo', 'Ente', '<w:spacing w:after="360"/><w:jc w:val="center"/>', '<w:sz w:val="24"/>')}'
    '${_style('Sezione', 'Sezione', '<w:keepNext/><w:spacing w:before="280" w:after="100"/>', '<w:b/>')}'
    '${_style('Corpo', 'Corpo', '<w:spacing w:after="120" w:line="300" w:lineRule="auto"/><w:jc w:val="both"/>', '')}'
    '${_style('Firma', 'Firma', '<w:spacing w:before="360"/>', '')}'
    '</w:styles>';

/// Crea un file Word (.docx) del verbale.
Uint8List verbaleToDocx(Verbale v) {
  final body = buildVerbaleBlocks(v).map(_paragraph).join();
  final document = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:body>$body<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
      '<w:pgMar w:top="1417" w:right="1134" w:bottom="1134" w:left="1134" w:header="708" w:footer="708" w:gutter="0"/>'
      '</w:sectPr></w:body></w:document>';

  final archive = Archive();
  void add(String name, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  add('[Content_Types].xml', _contentTypes);
  add('_rels/.rels', _rels);
  add('word/_rels/document.xml.rels', _docRels);
  add('word/document.xml', document);
  add('word/styles.xml', _styles);
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
