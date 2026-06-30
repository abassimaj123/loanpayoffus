import 'strings_en.dart';

class AppStringsES implements AppStrings {
  // App / nav
  final appTitle = 'Loan Payoff US';
  final navCalculator = 'Calculadora';
  final navPayoffPlan = 'Plan de Pago';
  final navComparison = 'Comparar';
  final navGoals = 'Metas';
  final navHistory = 'Historial';

  // Shared
  final enterLoan = 'Ingresa los datos del préstamo en la Calculadora';

  // Calculator
  final loanType = 'Tipo de Préstamo';
  final loanAmount = 'Monto del Préstamo';
  final interestRate = 'Tasa de Interés';
  final monthlyPayment = 'Pago Mensual';
  final extraPayment = 'Pago Extra';
  final youCouldSave = 'PODRÍAS AHORRAR';
  final inInterest = 'en interés';
  final faster = 'antes';
  final payoffTimeline = 'PLAZO DE PAGO';
  final withoutExtra = 'SIN EXTRA';
  final payoff = 'Liquidación';
  final interest = 'Interés';
  final totalPaid = 'Total pagado';
  final debtFreeDate = 'Libre de deuda';

  // Payoff Plan
  final months = 'Meses';
  final balance = 'Saldo';
  final monthLabel = 'Mes';
  final payment = 'Pago';
  final principal = 'Capital';
  final colMo = 'Mes';
  final balanceChart = 'Saldo en el Tiempo';
  final normalLabel = 'Normal';
  final withExtraLabel = 'Con Extra';

  // Comparison
  final extraScenarios = 'Escenarios de Pago Extra';
  final extraMo = 'Extra/mes';
  final saved = 'Ahorrado';
  final none = 'Ninguno';
  final interestSavedChart = 'Interés Ahorrado vs Pago Extra';

  // Goals
  final payoffMilestones = 'Hitos de Pago';
  final paid25 = '25% pagado';
  final paid50 = '50% pagado';
  final paid75 = '75% pagado';
  final paidOff = '¡Liquidado!';
  final currentPayoffDate = 'Fecha de Liquidación';
  final interestSavedExtra = 'Interés Ahorrado con Pago Extra';
  final setPayoffGoal = 'Establecer Meta de Pago';
  final chooseTargetDate = 'Elegir Fecha Objetivo';
  final goalPrefix = 'Meta:';
  final extraRequired = 'Pago Extra Requerido';
  final perMonth = 'por mes';

  // Settings
  final settingsTitle = 'Configuración';
  final language = 'Idioma';
  final support = 'Soporte';
  final contactSupport = 'Contactar Soporte';
  final rateApp = 'Valorar la App';
  final privacyPolicy = 'Política de Privacidad';
  final discover = 'Descubrir';
  final calcSuite = 'Suite de Calculadoras Financieras';

  // Premium
  final premiumActive = 'Premium Activo';
  final premiumSubtitle = 'Historial ilimitado · Sin anuncios · Exportar PDF';
  final getPremium = 'Obtener Premium';
  final getPremiumBtn = 'Obtener Premium';
  final restorePurchase = 'Restaurar Compra';
  final adFreeMinFree = 'Ver anuncio 60 min gratis';
  final loading = 'Cargando...';

  // History
  final historyEmpty = 'Aún no hay cálculos guardados';
  final clearHistory = 'Borrar Historial';
  final clearHistoryMsg = '¿Eliminar todos los cálculos guardados?';
  final cancel = 'Cancelar';
  final clearAll = 'Borrar todo';
  final unlockUnlimited = 'Desbloquear ilimitado';
  final extraSaved = 'Extra';
  final interestLabel = 'Interés';

  // Debt Strategy
  final navDebtStrategy = 'Estrategia';

  // History Detail
  final historyDetail = 'Detalle del Préstamo';
  final inputs = 'Datos';
  final results = 'Resultados';
  final loanTypeLabel = 'Tipo de Préstamo';
  final shareLabel = 'Compartir';
  final exportPdf = 'Exportar PDF';
  final disclaimer =
      'Solo para fines informativos. Consulte a un asesor financiero.';
  final calculatedWith = 'Calculado con Loan Payoff US';
  final payoffDate = 'Fecha de liquidación';
  final schedule = 'Calendario';
  final pdfExportedSuccess = 'PDF exportado';
  final debtFreeBy = 'Libre de deuda el';
  final payoffIn = 'Liquida en';

  // Backup / restore
  final backupRestore = 'Copia de seguridad';
  final backupSubtitle = 'Exporta o restaura tus deudas y pagos';
  final exportBackup = 'Exportar copia';
  final exportBackupDesc =
      'Guarda todas las deudas y el historial de pagos como CSV';
  final importBackup = 'Importar copia';
  final importBackupDesc = 'Restaura desde un CSV exportado previamente';
  final backupPasteHint = 'Pega aquí el contenido de tu copia CSV';
  final backupParseError = 'No se pudo leer esta copia.';
  final backupReplaceTitle = '¿Restaurar copia?';
  final backupReplaceBody =
      'Se encontraron {debts} deudas y {payments} pagos. ¿Reemplazar tus datos actuales o fusionar la copia con ellos?';
  final backupMerge = 'Fusionar';
  final backupReplace = 'Reemplazar';
  final backupImported = 'Copia restaurada';
  final backupExported = 'Copia lista para compartir';
  final backupSkipped = '{n} fila(s) inválida(s) omitida(s)';
  final backupErrEmpty = 'Nada que importar — pega tu copia primero.';
  final backupErrNotBackup = 'Este no es un archivo de copia de Loan Payoff US.';
  final backupErrNoDebts = 'No se encontraron deudas válidas en esta copia.';
  final backupErrColumns = 'Faltan columnas o están mal formadas.';
}
